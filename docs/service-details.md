# Service Details

Neon Hub is more than just a voice assistant. It is a collection of services that can be used independently or together to create a powerful AI server. Each service is a Docker container managed with Docker Compose.

## Service management

Neon Hub leverages Docker Compose for container management. Service start/stop/restart can be handled via `docker compose` from `/home/neon/compose` on the Hub itself, or through the web-based Simple Docker Manager described below.

### Container management UI

Neon Hub ships with [Simple Docker Manager](https://github.com/OscillateLabsLLC/simple-docker-manager), a lightweight web UI for viewing container status and logs, and restarting services. It is available at `https://manager.neon-hub.local` (or `http://neon-hub.local:3000`). The default username is `neon`; the password is generated at install time and stored in `ansible/neon_hub_secrets.yaml`.

## Network Discovery (mDNS)

Neon Hub advertises itself on the local network using [Avahi](https://avahi.org/), an mDNS/DNS-SD service. This allows Neon Node apps to automatically discover available Hubs on the same network using the "Scan for Hubs" feature.

The Hub advertises as service type `_neon-hub._tcp` on port 8082 (the HANA API endpoint).

### Verifying discovery

From a Linux machine on the same network:

```bash
avahi-browse -r _neon-hub._tcp
```

From a macOS machine:

```bash
dns-sd -B _neon-hub._tcp local.
```

You should see your Hub appear with its hostname and port.

### Troubleshooting discovery

If your Hub is not discoverable:

1. Verify avahi-daemon is running: `systemctl status avahi-daemon`
2. Check the service file exists: `ls /etc/avahi/services/neon-hub.service`
3. Ensure your firewall allows mDNS traffic (UDP port 5353)
4. Verify the Hub and the scanning device are on the same network/subnet

## Configuration tool

Neon Hub ships with a configuration tool that simplifies common tasks such as changing log levels, adding your own API keys for external services, and customizing other services. This tool is available at `https://neon-hub.local`.

The default username/password is `neon:neon`.

### Skill configuration tool

For editing individual skill settings (rather than core Neon configuration), Neon Hub also ships with [ovos-skill-config-tool](https://github.com/OscillateLabsLLC/ovos-skill-config-tool). It is available at `https://skill-config.neon-hub.local` (or `http://neon-hub.local:8010`). The default username is `neon`; the password is generated at install time and stored in `ansible/neon_hub_secrets.yaml`.

## Speech-To-Text (STT)

Also known as Automatic Speech Recognition (ASR), this is what enables the assistant to take your recorded voice and turn it into text that it can parse.

Different STT engines have different tradeoffs. For example, Neon's custom NeMo citrinet model is extremely fast (even on Raspberry Pi), but its quality is not as good as FasterWhisper, and it cannot handle heavily accented English as well. FasterWhisper has several model sizes available and, depending on your tolerance for waiting on the assistant, you can trade speed for quality and vice versa.

!!! note
    At this time, Neon Hub only ships with fasterwhisper.

- fasterwhisper: `http://neon-hub.local:8080`

## Text-To-Speech (TTS)

TTS allows the assistant to talk to you. Currently, Neon Hubs only ship with a custom Coqui model, which is optimized for Raspberry Pi CPU inference and performs extremely well on x86 processors.

- coqui: `http://neon-hub.local:9666`

## HTTP Services

Neon Hub uses [HANA](https://github.com/NeonGeckoCom/neon-hana) for RESTful API communications among different services. Non-developers will never need to use it, but it is available. Endpoint documentation and testing is available at `http://neon-hub.local:8082/docs`.

Neon Hub also has two web variations of [Iris](https://github.com/NeonGeckoCom/neon-iris). At `http://neon-hub.local:7860` there is a Gradio interface where you can type questions to Neon, speak directly to Neon, drop WAV files to speak to Neon, or change your personal information.

At `http://neon-hub.local:8001` there is a chat interface that includes a wakeword ("Hey Neon") for full voice interaction, similar to a smart speaker like Alexa. This interface is compatible with any modern smartphone, tablet, or computer.

!!!warning
    _At this time, Apple iOS devices do not have wake word support with audio playback due to security constraints imposed by Apple._

In order to fully leverage the Iris websat, you must either enable HTTPS and accept the self-signed certificate warning in your browser, or provide your own HTTPS certificate and configure DNS.

- hana: `http://neon-hub.local:8082`
- iris: `http://neon-hub.local:7860`
- iris-websat: `http://neon-hub.local:8001`

### Custom SSL certificate

The `nginx` service expects a public and private key to be located at `/home/neon/$HOSTNAME.crt` and `/home/neon/$HOSTNAME.key`, with the default value of `$HOSTNAME` being neon-hub.local. If you would like to use your own certificate, you can replace the existing files with your own and restart the nginx service.
