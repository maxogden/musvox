_ = require 'underscore'
$ = require 'jquery-browserify'
{EventEmitter} = require 'events'
inherits = require 'inherits'
{every, Logger} = require './utils'

###*
  Game state tracker.

  @param {object} options - an options object, `game` option is required
###
class Tracker
  inherits this, EventEmitter
  _.extend(this.prototype, Logger)

  constructor: (options) ->
    this.options = options or {}
    this.game = options.game
    this.sock = new WebSocket("ws://#{window.location.hostname}:8081/")
    this.seenIds = {}

    this.sock.onopen = =>
      $(window).on 'unload', => this.sock.close()
      $(window).on 'close', => this.sock.close()
      this.onOpen()

    this.sock.onmessage = (msg) =>
      msg = JSON.parse(msg.data)
      this.onMessage(msg)

  ###*
    Send a `message` over websocket.
  ###
  send: (msg) ->
    msg.reqId = _.uniqueId('reqId')
    this.sock.send(JSON.stringify(msg))
    msg.reqId

  ###*
    Send a chat `message` to other users.
  ###
  message: (message) ->
    this.send
      type: 'message'
      message: message

  musicblock: (musicblock) ->
    this.send
      type: 'musicblock'
      chunkIndex: musicblock.chunkIndex
      voxelVector: musicblock.voxelVector
      cid: musicblock.cid
      id: musicblock.id
      pos: musicblock.pos
      queue: musicblock.player.queue
      track:
        id: musicblock.player.cur.cur()?.id
        position: musicblock.player.sound?.position or 0

  ###*
    Callback for connection open with a server.
    This callback sets up a player's state notification.
  ###
  onOpen: ->
    interval = this.options.interval or 300
    yawPositionOld = undefined
    yawRotationOld = undefined
    every interval, =>
      needBroadcast = false

      yawPosition = this.game.game.controls.yawObject.position.clone()
      yawPosition.y = yawPosition.y - this.game.game.cubeSize
      needBroadcast = true unless _.isEqual(yawPosition, yawPositionOld)
      yawPositionOld = yawPosition.clone()

      yawRotation = this.game.game.controls.yawObject.rotation.clone()
      yawRotation.y = yawRotation.y + Math.PI / 2
      needBroadcast = true unless _.isEqual(yawRotation, yawRotationOld)
      yawRotationOld = yawRotation.clone()
      
      if needBroadcast
        this.send
          type: 'state'
          yawPosition: yawPosition
          yawRotation: yawRotation

  ###*
    Callback for every message received from a server.

    @param {object} msg - received message
  ###
  onMessage: (msg) ->
    if msg.type == 'state'
      if not this.seenIds[msg.id]
        this.log("connected: #{msg.id}")
        this.emit 'user:new', msg
        this.seenIds[msg.id] = true
      else
        this.emit 'user:state', msg

    else if msg.type == 'close'
      this.log("disconnected: #{msg.id}")
      this.emit 'user:close', msg.id
      delete this.seenIds[msg.id]

    else if msg.type == 'message'
      this.emit 'user:message', msg.id, msg.message

    else if msg.type == 'musicblock'
      msg.silent = true
      msg.show = true
      this.game.addMusicBlock(msg)

    else if msg.type == 'musicblocks'
      console.log msg
      for block in msg.blocks
        block.silent = true
        block.show = true
        this.game.addMusicBlock(block)

    else if msg.type == 'musicblock:reply'
      musicBlock = this.game.hasMusicBlock(msg.cid)
      if musicBlock
        musicBlock.id = msg.musicblockId

    else
      console.log 'unknown message type', msg

module.exports = {Tracker}
