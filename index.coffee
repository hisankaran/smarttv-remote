dgram = require 'dgram'
url = require 'url'
readline = require 'readline'
headerParser = require 'parse-headers'
request = require 'request-promise'
toXML = require 'toxml'
parserXML = require 'parser-xml'
program = require 'commander'

SSDP_HOST = '239.255.255.250'
SSDP_PORT = 1900
SSDP_MX = 1
SSDP_ST = 'udap:rootservice'
COMMANDS = {
  POWER: 1
  0: 2
  1: 3
  2: 4
  3: 5
  4: 6
  5: 7
  6: 8
  7: 9
  8: 10
  9: 11
  UP: 12
  DOWN: 13
  LEFT: 14
  RIGHT: 15
  OK: 20
  HOME_MENU: 21
  BACK: 23
  VOLUME_UP: 24
  VOLUME_DOWN: 25
  MUTE_TOGGLE: 26
  CHANNEL_UP: 27
  CHANNEL_DOWN: 28
  BLUE: 29
  GREEN: 30
  RED: 31
  YELLOW: 32
  PLAY: 33
  PAUSE: 34
  STOP: 35
  FAST_FORWARD: 36
  REWIND: 37
  SKIP_FORWARD: 38
  SKIP_BACKWARD: 39
  RECORD: 40
  RECORDING_LIST: 41
  REPEAT: 42
  LIVE_TV: 43
  EPG: 44
  PROGRAM_INFO: 45
  ASPECT_RATIO: 46
  EXTERNAL_INPUT: 47
  PIP_SECONDARY_VIDEO: 48
  SHOW_SUBTITLE: 49
  PROGRAM_LIST:50
  TELE_TEXT: 51
  MARK: 52
  '3D_VIDEO': 400
  '3D_LR': 401
  DASH: 402
  PREV_CHANNEL: 403
  FAV_CHANNEL: 404
  QUICK_MENU: 405
  TEXT_OPTION: 406
  AUDIO_DESC: 407
  ENERGY_SAVING: 409
  AV_MODE: 410
  SIMPLINK: 411
  EXIT: 412
  SWITCH_VIDEO: 416
  APPS: 417
}

class Remote
  constructor: ()->
    @session = null
    @listening_for_user_action = false
    @options = program
      .option('-p, --pair-code [number]', '6 digit pairing code')
      .parse(process.argv)
    @setupPrompt()
    @scanForDevices()

  scanForDevices: ()->
    console.log 'Searching for devices...'
    timeout = null
    ssdp_request = new Buffer("M-SEARCH * HTTP/1.1\r\n" + \
        "HOST: #{ SSDP_HOST }:#{ SSDP_PORT }\r\n" + \
        "MAN: \"ssdp:discover\"\r\n" + \
        "MX: #{ SSDP_MX }\r\n" + \
        "ST: #{ SSDP_ST }\r\n\r\n" + \
        "USER-AGENT: iOS/5.0 UDAP/2.0 iPhone/4\r\n")
    client = dgram.createSocket('udp4')
    client.on('message', (res, replyFrom)=>
      @parseHost(res)
      clearTimeout(timeout)
      client.close()
    )
    client.send(ssdp_request, 0, ssdp_request.length, SSDP_PORT, SSDP_HOST, (err)->
      if err then console.log 'Error connecting to network\n', err
    )
    timeout = setTimeout(()->
      console.log 'No devices found, please make sure the device is ON and connected to network...'
      client.close()
      process.exit()
    , 30000)

  parseHost: (res)->
    res = headerParser res.toString()
    if not res.location then return console.log 'Error, invalid response', res
    @location = url.parse res.location
    @udap_base_url = "#{ @location.protocol }//#{ @location.hostname }:#{ @location.port }/roap/api/"
    if not @options.pairCode then @requestPairingCode()
    else
      @initSession().then(()=>
        @printCommandList()
        @prompt()
      )

  requestPairingCode: ()->
    console.log 'Requesting Pairing Code...'
    @apiRequest('auth', {auth: {type: 'AuthKeyReq'}}).then((res)->
      console.log 'Request success, please run the script with pairing code you receive in device...'
      process.exit()
    ).catch((err)->
      console.error 'Something went wrong...'
      console.error err
    )

  initSession: ()->
    console.log 'Initiating the session with the Device...'
    @apiRequest('auth', {auth: {type: 'AuthReq', value: @options.pairCode}}).then((res)->
      parserXML.parse(res, (err, body)=>
        @session = body.envelope.session[0]
      )
    ).catch((err)->
      console.error 'Somthing went wrong while intiating the session...'
      console.error err
    )

  sendCommand: (cmd)->
    @apiRequest('command', {command: {name: 'HandleKeyInput', value: cmd}}).then((res)->
    ).catch((err)->
      console.error 'Somthing went wrong while sending the command...'
      console.error err
    )

  apiRequest: (endpoint, data)->
    request_data = "<?xml version=\"1.0\" encoding=\"utf-8\"?>#{ toXML(data) }"
    request.post({
      url: "#{ @udap_base_url }#{ endpoint }"
      body: request_data
      headers: {
        'content-type': 'text/xml'
        'cache-control': 'no-cache'
      }
    })

  printCommandList: ()->
    console.log "Commands List:\n#{ Object.keys(COMMANDS).join(', ') }"

  setupPrompt: ()->
    @rl = readline.createInterface(process.stdin, process.stdout, (str)->
      commands = Object.keys(COMMANDS)
      hits = commands.filter((c)-> return c.toLowerCase().indexOf(str) == 0 )
      return [hits.length ? hits : commands, str]
    )

  prompt: ()->
    process.stdout.moveCursor(0, 1)
    @rl.setPrompt('enter your command > ');
    @rl.prompt();
    if not @listening_for_user_action
      @listening_for_user_action = true
      @rl.on('line', (cmd)=>
        cmd = cmd.toUpperCase()
        if COMMANDS[cmd]
          @sendCommand(COMMANDS[cmd]).then(()=>
            @prompt()
          )
        else if cmd is 'Q' or cmd is 'QUIT'
          process.exit()
        else if cmd is 'H' or cmd is 'HELP'
          @printCommandList()
          @prompt()
        else @prompt()
      )

# Lets run the remote
new Remote()