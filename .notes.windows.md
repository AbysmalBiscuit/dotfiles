# Notes (Windows)

## Dolby Atmos (DolbyDAXAPI) memory leak

The Dolby Atmos / Dolby Audio drivers that OEMs pre-install can leak memory. To reclaim the memory, the service needs to be restarted:

```powershell
Restart-Service DolbyDAXAPI -Force

# If you have `sudo` mode enabled
sudo powershell -Command "Restart-Service DolbyDAXAPI -Force"
```
