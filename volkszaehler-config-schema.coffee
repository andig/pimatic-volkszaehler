# #pimatic-volkszaehler plugin configuration options
module.exports = {
  title: "Volkszaehler plugin config options"
  type: "object"
  properties:
    middleware:
      description: "Middleware URL"
      type: "string"
      default: "http://127.0.0.1/middleware.php"
    mode:
      description: "Connection mode for middleware"
      type: "string"
      enum: ["push", "pull"]
      default: "pull"
    interval:
      description: "Polling interval for channel updates in seconds when mode == pull"
      type: "number"
      default: 60
}