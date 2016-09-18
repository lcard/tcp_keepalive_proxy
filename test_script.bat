
start "SERVER" perl test_server.pl

start "PROXY 10" perl select_proxy.pl 1250 127.0.0.1 1235 
start "PROXY 9" perl select_proxy.pl 1249 127.0.0.1 1250 
start "PROXY 8" perl select_proxy.pl 1248 127.0.0.1 1249 
start "PROXY 6" perl select_proxy.pl 1246 127.0.0.1 1248 
start "PROXY 5" perl select_proxy.pl 1245 127.0.0.1 1247 
start "PROXY 7" perl select_proxy.pl 1247 127.0.0.1 1246 
start "PROXY 4" perl select_proxy.pl 1244 127.0.0.1 1245 
start "PROXY 3" perl select_proxy.pl 1243 127.0.0.1 1244 
start "PROXY 2" perl select_proxy.pl 1242 127.0.0.1 1243 
start "PROXY 1" perl select_proxy.pl 1234 127.0.0.1 1242 

start "CLIENT" perl test_client.pl

