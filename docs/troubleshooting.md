# Troubleshooting

For more technical users, you can access the RabbitMQ management console at `http://neon-hub.local:15672`. The default username and password are `neon` and `neon` respectively.

You can also use Neon's `mana` command to interact with the Neon AI system. It is installed in the neon-messagebus container. To use it, run `docker exec -it $(docker ps -q -f name=neon-messagebus) mana -h`.

## Updating Neon Hub fails with `General error: Error response from daemon: Conflict.`

Sometimes you need to remove the existing containers to update. You can do so with the following commands. Please note that it will remove ALL running and saved containers, so if you are running containers besides from Neon Hub, they will also be shut down:

```bash
docker kill $(docker ps -q)
docker container rm $(docker container ls -aq)
```

## Failure to install Docker

Sometimes the Docker installation fails. If this happens, you can try the following:
`sudo rm /etc/apt/sources.list.d/docker*`

Then re-run the installer.

## Neon Node client not running

Try restarting the Neon Node service:

```bash
systemctl --user -M neon@ restart neon-node
```

If the service does not start, check the logs:

```bash
journalctl --user -M neon@ -xleu neon-node
```
