# Configuration

[More configuration information is available in the Neon documentation.](https://neongeckocom.github.io/neon-docs/quick_reference/configuration/)

All configuration is done in the `neon.yaml` file. This file is located in the `/home/neon/xdg/neon/neon.yaml` directory by default. After making changes to the file, you must restart the Neon core services in Yacht for the changes to take effect.

Neon core services:

- neon-gui
- neon-enclosure
- neon-audio
- neon-skills
- neon-speech
- neon-messagebus

## Common configuration options

### Logging verbosity

To increase or decrease the verbosity of the logs, change the `LOG_LEVEL` value. The default value is `INFO`.

```yaml
LOG_LEVEL: DEBUG
```

All valid Python logging levels are available. For reference, see the [Python logging documentation](https://docs.python.org/3/library/logging.html#logging-levels).

### Units of measurement

To switch between metric and imperial units, change the `system_unit` value. The default value is `imperial`.

```yaml
system_unit: metric
```

To switch between 12-hour and 24-hour time, change the `time_format` value. The default value is `half`, or 12-hour time.

```yaml
time_format: full
```

## Installing additional skills and plugins

Each Neon Core service is a Docker container. To install a new service, you need to add it to the `neon.yaml` file and then restart the services.

For each package you want to install, add a [pip-compatible package name](https://pip.pypa.io/en/stable/reference/requirements-file-format/) to the `default_skills`, `extra_dependencies.voice`, `extra_dependencies.audio`, or `extra_dependencies.phal` lists in the `neon.yaml` file.

Please note that the Python environments in each container do not persist past reboots, so you _must_ use the `neon.yaml` file to install new packages. Failure to do so will result in the package being removed when the container is restarted.

Examples:

```yaml
default_skills: # Add skills to install here
  - neon-skill-alerts
  # - other pip-compatible package names
extra_dependencies:
  global: # Installs in all containers/services
    - requests
  skills: # Add neon-skill dependencies to install here
    - neon-skill-alerts
  voice: # Add neon-speech dependencies to install here
    - ovos-stt-server
  audio: # Add neon-audio dependencies to install here
    - ovos-tts-plugin-beepspeak
  enclosure: # Add neon-enclosure dependencies to install here
    - ovos-PHAL-plugin-homeassistant
```

## External services

The default `neon.yaml` file includes a commented section for using your own API keys for external services. It looks like this:

```yaml
# keys:
#   api_services:
#     alpha_vantage:
#       api_key: CUSTOM_KEY_HERE
#     open_weather_map:
#       api_key: CUSTOM_KEY_HERE
#     wolfram_alpha:
#       api_key: CUSTOM_KEY_HERE
```

To use your own API keys, uncomment the section (remove the `# `) and replace `CUSTOM_KEY_HERE` with your key.

Alpha Vantage is used for stock prices, Open Weather Map is used for weather information, and Wolfram Alpha is used for general knowledge queries.

- Alpha Vantage: [Get your API key](https://www.alphavantage.co/support/#api-key)
- Open Weather Map: [How to get an API key](https://home.openweathermap.org/appid)
- Wolfram Alpha: [Get your API key](https://products.wolframalpha.com/api/)

The Wolfram Alpha API key site has been known to fail when an ad blocker is enabled. If you are having trouble getting your key, try disabling your ad blocker.

Future versions of Neon Hub will include a web interface for managing these keys.

## Skill settings

Each skill has its own settings file located in the `/home/neon/xdg/neon/skills/$SKILL_NAME/settings.json` directory. These settings can be modified to change the behavior of the skill. Some skills require you to restart the neon-skills service in Yacht for the changes to take effect, although many skills automatically read the settings file each time and do not require a restart.
