<##>

#Variable Set

$Service = "VAST Uranus Watch Dog"

#Stop Service, wait 30 seconds, then restart service

stop-service -DisplayName $Service

Start-Sleep -seconds 30

start-service  -DisplayName $Service