from neon_utils.process_utils import start_systemd_service
from neon_nodes.voice_client import NeonVoiceClient

start_systemd_service(NeonVoiceClient().watchdog())
