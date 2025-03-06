# Services

Neon Hub comes with an nginx reverse proxy that routes traffic to the appropriate service.

!!! note
    If you chose a different hostname during the installation process, replace `neon-hub.local` with your hostname or IP address.

The following paths are available (friendly URLs will only work if you have set up your `/etc/hosts` file or DNS server):

| Service        | Friendly URL                                                                   | URL with port                                              |
| -------------- | ------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| Fasterwhisper  | [https://fasterwhisper.neon-hub.local](https://fasterwhisper.neon-hub.local)   | [http://neon-hub.local:8080](http://neon-hub.local:8080)   |
| Coqui          | [https://coqui.neon-hub.local](https://coqui.neon-hub.local)                   | [http://neon-hub.local:9666](http://neon-hub.local:9666)   |
| HANA           | [https://hana.neon-hub.local](https://hana.neon-hub.local)                     | [http://neon-hub.local:8082](http://neon-hub.local:8082)   |
| Iris           | [https://iris.neon-hub.local](https://iris.neon-hub.local)                     | [http://neon-hub.local:7860](http://neon-hub.local:7860)   |
| Iris-Websat    | [https://iris-websat.neon-hub.local](https://iris-websat.neon-hub.local)       | [http://neon-hub.local:8001](http://neon-hub.local:8001)   |
| Yacht          | [https://yacht.neon-hub.local](https://yacht.neon-hub.local)                   | [http://neon-hub.local:8000](http://neon-hub.local:8000)   |
| RMQ-Admin      | [https://rmq-admin.neon-hub.local](https://rmq-admin.neon-hub.local)           | [http://neon-hub.local:15672](http://neon-hub.local:15672) |
| Libretranslate | [https://libretranslate.neon-hub.local](https://libretranslate.neon-hub.local) | [http://neon-hub.local:5000](http://neon-hub.local:5000)   |

Please note that the Iris-Websat service will only work with HTTPS, requiring additional configuration, although you can see your chat history and the Iris interface at `http://neon-hub.local:8001`. The Iris service at `http://neon-hub.local:7860` will work with HTTP.

## Local access to addresses

### Hosts file

Add the following to the `/etc/hosts` file on the computer you are using to access the Neon Hub (not on the Hub itself):

```bash
10.10.10.10 neon-hub.local fasterwhisper.neon-hub.local coqui.neon-hub.local hana.neon-hub.local iris.neon-hub.local iris-websat.neon-hub.local yacht.neon-hub.local rmq-admin.neon-hub.local libretranslate.neon-hub.local
```

Replace `10.10.10.10` with the IP address of your Neon Hub.

### DNS

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
libretranslate.neon-hub.local IN A 10.10.10.10
```

Replace `10.10.10.10` with the IP address of your Neon Hub.
