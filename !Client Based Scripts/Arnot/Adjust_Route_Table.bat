@Echo off

::Check for and Remove manual routes
route delete 192.168.1.30  
route delete 192.168.1.30 

::Re-Create manual routes
route -p add 192.168.1.30 MASK 255.255.255.255 192.168.2.1
route -p add 192.168.1.31 MASK 255.255.255.255 192.168.2.1

::Send Message to console this is complete

echo "Routes have been re-mapped. Please try to access the shared drives"

timeout /t 5