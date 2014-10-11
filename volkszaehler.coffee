# #Volkszaehler plugin

module.exports = (env) ->

  # Require the bluebird promise library
  Promise = env.require 'bluebird'

  # Require the [cassert library](https://github.com/rhoot/cassert).
  assert = env.require 'cassert'

  # Require request
  request = require 'request-promise'

  # ###VolkszaehlerPlugin class
  class VolkszaehlerPlugin extends env.plugins.Plugin

    devices: {}

    # ####init()
    # The `init` function is called by the framework to ask your plugin to initialise.
    #
    # #####params:
    #  * `app` is the [express] instance the framework is using.
    #  * `framework` the framework itself
    #  * `config` the properties the user specified as config for your plugin in the `plugins`
    #     section of the config.json file
    #
    init: (app, @framework, @config) =>
      # get volkszaehler capability definition
      assert @config.middleware?

      #!! why the heck are brackets needed?
      #!! why is  .catch env.logger.error  not possible?
      @_capabilities = request({ uri: @config.middleware + '/capabilities.json', simple: true, transform: JSON.parse })
        .then (json) ->
          definitions = json?.capabilities?.definitions
          assert definitions?
          return Promise.resolve definitions
        .error (error) ->
          env.logger.error "Error getting #{error.options.uri}: #{error.response.statusCode}"
        .catch (error) ->
          env.logger.error error

      # accept GET and POST
      app.get( '/volkszaehler/:uuid', (req, res) =>
        assert req.params.uuid

        timestamp = req.param 'timestamp'
        value = req.param 'value'
        if timestamp and value
          res.send 'OK'
          @updateRegisteredDevice req.params.uuid, parseFloat(timestamp), parseFloat(value)
        else
          res.status(400).send 'ERROR'
      ).post( '/volkszaehler/:uuid', (req, res) =>
        assert req.params.uuid

        hook = req.param 'hook'
        timestamp = hook?.timestamp
        value = hook?.value
        if timestamp and value
          res.send 'OK'
          @updateRegisteredDevice req.params.uuid, parseFloat(timestamp), parseFloat(value)
        else
          res.status(400).send 'ERROR'
      )

      # register device type
      deviceConfigDef = require("./device-config-schema")
      @framework.deviceManager.registerDeviceClass("Volkszaehler", {
        configDef: deviceConfigDef.Volkszaehler,
        createCallback: (config) =>
          return new VolkszaehlerDevice(config, this)
      })

    # ####registerDevice()
    # `registerDevice` registeres the channel device with the volkszaehler plugin
    # this allows the plugin to update the device when it receives push notifications from
    # volkszaehler middleware
    #
    # #####params:
    #  * `id` deviceId by which it can be obtained from the deviceManager
    #  * `uuid` volkszaehler channel id
    #
    registerDevice: (id, uuid) =>
      if @devices[uuid]?
        throw new assert.AssertionError("duplicate channel uuid \"#{uuid}\"")
      @devices[uuid] = id

    # ####updateRegisteredDevice()
    # `updateRegisteredDevice` updates the device when push notifications are received from the
    # volkszaehler middleware
    #
    # #####params:
    #  * `uuid` volkszaehler channel id
    #  * `timestamp` update timestamp in ms (bigint)
    #  * `value` updated value (float)
    #
    updateRegisteredDevice: (uuid, timestamp, value) =>
      # console.log "updateRegisteredDevice:", uuid, timestamp, value
      deviceId = @devices[uuid]
      @framework.deviceManager.getDeviceById(deviceId).update(timestamp, value) if deviceId

    # ####getCapabilitiesByType()
    # `getCapabilitiesByType` returns capability definition by entity type
    #
    # #####params:
    #  * `type` volkszaehler entity type, e.g. 'power'
    #
    getCapabilitiesByType: (type) =>
      @_capabilities.then (capabilities) ->
        result = (entityCaps for entityCaps in capabilities.entities when entityCaps.name is type)
        assert result.length is 1
        return Promise.resolve result[0]

  class VolkszaehlerDevice extends env.devices.Sensor
    # attributes
    attributes:
      value:
        description: "Channel value"
        type: "number"

    # actions
    actions:
      update:
        params:
          timestamp:
            type: "number"
          value:
            type: "number"
        description: "Tuple updated"

    _timestamp = null
    _value = null

    # ####constructor()
    # Initialize device by reading entity definition from middleware
    #
    constructor: (@config, @plugin) ->
      # console.log "VolkszaehlerDevice"
      @name = config.name
      @id = config.id

      # inherit middleware from plugin if not defined
      @config.middleware = @plugin.config.middleware unless @config.middleware

      # register device for updates
      @plugin.registerDevice @id, config.uuid

      # link to middleware entity definition
      @config.xlink = @config.middleware + "/entity/#{@config.uuid}.json"

      # get entity definition
      @_definition = request({ uri: @config.xlink, simple: true, transform: JSON.parse })
        .then (json) ->
          entityDef = json?.entity
          assert entityDef
          return Promise.resolve entityDef
        .error (error) ->
          env.logger.error "Error getting #{error.options.uri}: #{error.response.statusCode}"
        .catch (error) ->
          env.logger.error error

      # get entity capabilities
      @_capabilities = @_definition.then (definition) =>
        return @plugin.getCapabilitiesByType definition.type

      # set relevant capabilities
      @_capabilities.then (capabilities) =>
        @attributes['value'].unit = capabilities.unit

      super()

    # ####getTimestamp()
    # Get timestamp of last update in ms
    #
    getTimestamp: -> Promise.resolve(@_timestamp)

    # ####getValue()
    # Get value of last update in defined unit
    #
    getValue: -> Promise.resolve(@_value)

    _setTuple: (timestamp, value) ->
      if @_timestamp is timestamp and @_value is value then return
      @_timestamp = timestamp
      @_value = value
      @emit "value", value

    # ####update()
    # Update timestamp/value
    #  * `timestamp` update timestamp in ms (bigint)
    #  * `value` updated value (float)
    #
    update: (timestamp, value) ->
      @_setTuple timestamp, value

  # ###Finally
  # Create a instance of my plugin
  volkszaehlerPlugin = new VolkszaehlerPlugin
  # and return it to the framework.
  return volkszaehlerPlugin
