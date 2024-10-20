# Neon Hub

Neon Hub is a central server for artificial intelligence, powered by Neon AI®. It is designed to be a private, offline, and secure alternative to cloud-based AI assistants like Alexa, Google Assistant, and Siri. A Neon Hub can run on any consumer computer built within the last 5 years, running the Linux operating system, and can be accessed from any device on the same network. Neon Hub is designed to be easy to set up and use, with a web interface for managing services and a RESTful API for developers. A GPU is not required and is currently not supported, but future versions will support GPU acceleration.

A Neon Hub can be used with any number of Neon Nodes, which can be as small as a Raspberry Pi Zero W. Nodes can be placed throughout a home or office, and can be used to interact with the Hub using voice commands, text, or a web interface. The Hub can be used to control smart home devices, answer questions, play music, and more.

Neon Hub is perfect for:

- Privacy-conscious individuals
- Retail kiosks
- Municipalities
- Educational institutions
- Hospitals
- Hotels

## System Requirements

| Component | Minimum | Recommended    |
| --------- | ------- | -------------- |
| CPU       | 4 cores | 8 cores        |
| Memory    | 4GB     | 8GB            |
| Disk      | 75GB    | 150GB SSD/NVME |

~25GB for Docker images, 7GB for OS, 45GB for data

Neon Hub runs on both x86 and ARM CPUs.

### Approximate Docker image sizes

| Service          | Size     |
| ---------------- | -------- |
| neon-gui         | 826MB    |
| neon-enclosure   | 1.2GB    |
| neon-audio       | 3GB      |
| neon-skills      | 2.6GB    |
| neon-speech      | 3.6GB    |
| neon-messagebus  | 778MB    |
| neon-api-proxy   | 746MB    |
| neon-hana        | 443MB    |
| neon-iris        | 1.78GB   |
| neon-iris-websat | 1.61GB   |
| coqui            | 1.3GB    |
| fasterwhisper    | 1.94GB   |
| yacht            | 415MB    |
| **Total**        | 25.338GB |

Note that the total image size is greater than the actual disk space consumed due to shared dependencies.

## Installation

Clone this repository (`git clone https://github.com/NeonGeckoCom/neon-hub-installer`) and run `sudo ./installer.sh`. It will install prerequisites, then take you through a guided setup process.

## Post-Installation

### Configuration

All configuration is done in the `neon.yaml` file. This file is located in the `/home/neon/xdg/neon/neon.yaml` directory by default. After making changes to the file, you must restart the Neon core services in Yacht for the changes to take effect.

Neon core services:

- neon-gui
- neon-enclosure
- neon-audio
- neon-skills
- neon-speech
- neon-messagebus

### Installing additional skills and plugins

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

### Skill settings

Each skill has its own settings file located in the `/home/neon/xdg/neon/skills/$SKILL_NAME/settings.json` directory. These settings can be modified to change the behavior of the skill. Some skills require you to restart the neon-skills service in Yacht for the changes to take effect, although many skills automatically read the settings file each time and do not require a restart.

### External services

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

Alpha Vantage: [Get your API key](https://www.alphavantage.co/support/#api-key)
Open Weather Map: [How to get an API key](https://home.openweathermap.org/appid)
Wolfram Alpha: [Get your API key](https://products.wolframalpha.com/api/)

The Wolfram Alpha API key site has been known to fail when an ad blocker is enabled. If you are having trouble getting your key, try disabling your ad blocker.

Future versions of Neon Hub will include a web interface for managing these keys.

### Troubleshooting

For more technical users, you can access the RabbitMQ management console at `http://neon-hub.local:15672`. The default username and password are `neon` and `neon` respectively. You can also use Neon's `mana` command to interact with the Neon AI system. It is installed in the neon-messagebus container. To use it, run `docker exec -it $(docker ps -q -f name=neon-messagebus) mana -h`.

#### Updating Neon Hub fails with `General error: Error response from daemon: Conflict.`

Sometimes you need to remove the existing containers to update. You can do so with the following commands. Please note that it will remove ALL running and saved containers, so if you are running containers besides from Neon Hub, they will also be shut down:

```bash
docker kill $(docker ps -q)
docker container rm $(docker container ls -aq)
```

#### Failure to install Docker

Sometimes the Docker installation fails. If this happens, you can try the following:
`sudo rm /etc/apt/sources.list.d/docker*`

Then re-run the installer.

### Services

Neon Hub comes with an nginx reverse proxy that routes traffic to the appropriate service. The following paths are available:

| Service       | Friendly URL                           | URL with port                 |
| ------------- | -------------------------------------- | ----------------------------- |
| Fasterwhisper | `https://fasterwhisper.neon-hub.local` | `http://neon-hub.local:8080`  |
| Coqui         | `https://coqui.neon-hub.local`         | `http://neon-hub.local:9666`  |
| HANA          | `https://hana.neon-hub.local`          | `http://neon-hub.local:8082`  |
| Iris          | `https://iris.neon-hub.local`          | `http://neon-hub.local:7860`  |
| Iris-Websat   | `https://iris-websat.neon-hub.local`   | `http://neon-hub.local:8001`  |
| Yacht         | `https://yacht.neon-hub.local`         | `http://neon-hub.local:8000`  |
| RMQ-Admin     | `https://rmq-admin.neon-hub.local`     | `http://neon-hub.local:15672` |

Please note that the Iris-Websat service will only work with HTTPS, although you can see your chat history and the Iris interface at `http://neon-hub.local:8001`.

### Local access to addresses

#### Hosts file

Add the following to the `/etc/hosts` file on the computer you are using to access the Neon Hub (not on the Hub itself):

```bash
10.10.10.10 neon-hub.local fasterwhisper.neon-hub.local coqui.neon-hub.local hana.neon-hub.local iris.neon-hub.local iris-websat.neon-hub.local yacht.neon-hub.local rmq-admin.neon-hub.local
```

Replace `10.10.10.10` with the IP address of your Neon Hub.

#### DNS

If you have a DNS server, you can add the following records:

```bash
neon-hub.local. IN A 10.10.10.10
fasterwhisper.neon-hub.local. IN A 10.10.10.10
coqui.neon-hub.local. IN A 10.10.10.10
hana.neon-hub.local. IN A 10.10.10.10
iris.neon-hub.local. IN A 10.10.10.10
iris-websat.neon-hub.local. IN A 10.10.10.10
yacht.neon-hub.local. IN A 10.10.10.10
rmq-admin.neon-hub.local. IN A 10.10.10.10
```

Replace `10.10.10.10` with the IP address of your Neon Hub.

## Exposed services

### Speech-To-Text (STT)

Also known as Automatic Speech Recognition (ASR), this is what enables the assistant to take your recorded voice and turn it into text that it can parse.

Different STT engines have different tradeoffs. For example, Neon's custom NeMo citrinet model is extremely fast (even on Raspberry Pi), but its quality is not as good as FasterWhisper, and it cannot handle heavily accented English as well. FasterWhisper has several model sizes available and, depending on your tolerance for waiting on the assistant, you can trade speed for quality and vice versa.

At this time, Neon Hub only ships with fasterwhisper.

- fasterwhisper: `http://neon-hub.local:8080`
- nemo: `http://neon-hub.local:8081`

### Text-To-Speech (TTS)

TTS allows the assistant to talk to you. Currently, Neon Hubs only ship with a custom Coqui model, which is optimized for Raspberry Pi CPU inference and performs extremely well on x86 processors.

- coqui: `http://neon-hub.local:9666`

### HTTP Services

Neon Hub uses HANA for RESTful API communications among different services. Non-developers will never need to use it, but it is available. Endpoint documentation and testing is available at `http://neon-hub.local:8082/docs`.

Neon Hub also has two web variations of Iris. At `http://neon-hub.local:7860` there is a Gradio interface where you can type questions to Neon, speak directly to Neon, drop WAV files to speak to Neon, or change your personal information.

At `http://neon-hub.local:8001` there is a chat interface that includes a wakeword ("Hey Neon") for full voice interaction, similar to a smart speaker like Alexa. This interface is compatible with any modern smartphone, tablet, or computer. _At this time, Apple iOS devices do not have wake word support with audio playback due to security constraints imposed by Apple._

In order to fully leverage the Iris websat, you must either enable HTTPS and accept the self-signed certificate warning in your browser, or provide your own HTTPS certificate and configure DNS.

- hana: `http://neon-hub.local:8082`
- iris: `http://neon-hub.local:7860`
- iris-websat: `http://neon-hub.local:8001`

#### Custom SSL certificate

The `nginx` service expects a public and private key pair to be located at `/home/neon/$HOSTNAME.local.crt` and `/home/neon/$HOSTNAME.local.key`, with the default value of `$HOSTNAME` being neon-hub.local. If you would like to use your own certificate, you can replace the existing files with your own and restart the nginx service in Yacht.

### Service management

Neon Hub leverages Docker Compose for container management. For ease of viewing logs and managing services, Yacht is installed on the server at `http://neon-hub.local:8000/#/apps`. The default username and password is `admin@yacht.local` and `pass` respectively. You can change your password in the User Settings section of Yacht. For more information on [how to set your password, see the docs](https://yacht.sh/docs/Pages/User_Settings).

For more usage information, [see the Yacht documentation](https://yacht.sh/docs/). The section on [applications](https://yacht.sh/docs/Pages/Applications) is particularly useful.

If you'd like to disable default services, this is the place to do it. This is your Hub - use only what you want!
