# Service Details

Neon Hub is more than just a voice assistant. It is a collection of services that can be used independently or together to create a powerful AI server. Each service is a Docker container that can be managed with Yacht, a web-based Docker management tool.

## Service management

Neon Hub leverages Docker Compose for container management. For ease of viewing logs and managing services, Yacht is installed on the server at `http://neon-hub.local:8000/#/apps`. The default username and password is `admin@yacht.local` and `pass` respectively. You can change your password in the User Settings section of Yacht. For more information on [how to set your password, see the docs](https://yacht.sh/docs/Pages/User_Settings).

For more usage information, [see the Yacht documentation](https://yacht.sh/docs/). The section on [applications](https://yacht.sh/docs/Pages/Applications) is particularly useful.

If you'd like to disable default services, this is the place to do it. This is your Hub - use only what you want!

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

Neon Hub uses HANA for RESTful API communications among different services. Non-developers will never need to use it, but it is available. Endpoint documentation and testing is available at `http://neon-hub.local:8082/docs`.

Neon Hub also has two web variations of Iris. At `http://neon-hub.local:7860` there is a Gradio interface where you can type questions to Neon, speak directly to Neon, drop WAV files to speak to Neon, or change your personal information.

At `http://neon-hub.local:8001` there is a chat interface that includes a wakeword ("Hey Neon") for full voice interaction, similar to a smart speaker like Alexa. This interface is compatible with any modern smartphone, tablet, or computer. 

!!!warning
    _At this time, Apple iOS devices do not have wake word support with audio playback due to security constraints imposed by Apple._

In order to fully leverage the Iris websat, you must either enable HTTPS and accept the self-signed certificate warning in your browser, or provide your own HTTPS certificate and configure DNS.

- hana: `http://neon-hub.local:8082`
- iris: `http://neon-hub.local:7860`
- iris-websat: `http://neon-hub.local:8001`

### Custom SSL certificate

The `nginx` service expects a public and private key pair to be located at `/home/neon/$HOSTNAME.crt` and `/home/neon/$HOSTNAME.key`, with the default value of `$HOSTNAME` being neon-hub.local. If you would like to use your own certificate, you can replace the existing files with your own and restart the nginx service in Yacht.
