use IO::Socket::INET;
 
# auto-flush on socket
$| = 1;
 
# creating a listening socket
my $socket = new IO::Socket::INET (
	LocalHost => '0.0.0.0',
	LocalPort => '1235',
	Proto => 'tcp',
	Listen => 5,
	Reuse => 1
);
die "cannot create socket $!\n" unless $socket;
print "server waiting for client connection on port 7777\n";
 
while(1)
{
	# waiting for a new client connection
	my $client_socket = $socket->accept();
 
	# get information about a newly connected client
	my $client_address = $client_socket->peerhost();
	my $client_port = $client_socket->peerport();
	print "connection from $client_address:$client_port\n";
 
	# read up to 1024 characters from the connected client
	my $data = "";
	while ($client_socket->recv($data, 1024)) {
		$size = length($data);
		print "received: $size\n";

		# write response data to the connected client
		my $time = time();
		$data .= "$time ok ";
		my $ssize = length($data);

		# Don't respond with message lengths divisible by 1024. 
		if ($ssize % 1024 == 0) {
			$data .= "fixup ";
			$ssize = length($data);
		}

		$client_socket->send($data);

		print "sent: $ssize\n";	
		if ($size < 1024) {
			last;
		}
 
	}

	# Simulate idle timeout of CNI2e
	sleep(1);

	# notify client that response has been sent
	print "Shutting down client connection.\n";
	shutdown($client_socket, 1);
}
 
$socket->close();