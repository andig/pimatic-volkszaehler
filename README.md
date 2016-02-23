pimatic volkszaehler plugin
===========================

Volkszaehler plugin enables connecting the [volkszaehler.org](http://volkszaehler.org) smart meter application to [pimatic](http://pimatic.org) automation server.

Plugin Configuration
-------------
You can load the plugin by editing your `config.json` to include:

    {
		"plugin": "volkszaehler",
		"middleware": "http://127.0.0.1/middleware.php", // url of the volkszaehler middleware
		"interval": 60 // Polling interval. Inherited from plugin if not defined.
		"mode": ["push", "pull"] // Update mode. Default is pull
    }

The middleware url is needed to retrieve the volkszaehler installation's capabilities, especially the [entity type definitions](https://github.com/volkszaehler/volkszaehler.org/blob/master/lib/Volkszaehler/Definition/EntityDefinition.json).

**NOTE** currently, volkszahler master branch does not contain the needed patches to push data to pimatic. Make sure that

	"mode": "pull"

as long as you're running a Volkszaehler version with API version <= 0.3

Device Configuration
-------------
Devices are linked to volkszaehler channels by specifying the `class`, `middleware` and `uuid` properties:

	...
	"devices": [
	{
		"id": "home-bezug",
		"name": "Kanal 1",
		"class": "Volkszaehler",
		"uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxx"
		// optional attributes - inherited from plugin if not defined
		"middleware": "http://127.0.0.1/middleware.php", // Url of the device's middleware
		"mode": ["push", "pull"] // Update mode
		"interval": 60 // Polling interval if mode == pull
	},
	...

As `middleware` can be configured per device, multiple volkszaehler installations can be connected as long as their capabiltiies match. If `middleware` is not configured, it will be inherited from the plugin settings.
