# #pimatic-volkszaehler plugin configuration options
module.exports = {
  title: "Volkszaehler plugin config options"
  type: "object"
  properties:
    middleware:
      description: "Middleware URL"
      type: "string"
      default: "http://127.0.0.1/middleware.php"
}