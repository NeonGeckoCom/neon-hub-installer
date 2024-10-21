# System Requirements

| Component | Minimum | Recommended    |
| --------- | ------- | -------------- |
| CPU       | 4 cores | 8 cores        |
| Memory    | 4GB     | 8GB            |
| Disk      | 75GB    | 150GB SSD/NVME |

~25GB for Docker images, 7GB for OS, the rest for data.

Neon Hub runs on both x86 and ARM CPUs.

## Approximate Docker image sizes (subject to change)

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

!!! note
    The total image size is greater than the actual disk space consumed due to shared dependencies.
