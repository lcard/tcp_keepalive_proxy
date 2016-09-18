use strict;
use warnings;
use IO::Socket::INET;
 
# auto-flush on socket
$| = 1;
 
# create a connecting socket
my $socket = new IO::Socket::INET (
	PeerHost => '127.0.0.1',
	PeerPort => '1234',
	Proto => 'tcp',
);
die "Cannot connect to the server $!\n" unless $socket;
print "Connected to the server.\n";

my $req = "";

while (1) {

	# data to send to a server
	$req .= time() . ' request ';
	
	#Never send data in lengths divisible by 1024.
	if (length($req) % 1024 == 0) {
		$req .= " fixup";
	}
	my $size = $socket->send($req);
	if ($size) {
		print "sent: $size\n";
	} else {
		print "Socket send() error. Did remote close it on me?\n";
		print "Better fail the channel!\n";
		exit();
	} 
	
	# receive a response of up to 1024 characters from server
	my $response = "";
	while ($size = $socket->recv($response, 1024)){
		if ($size) {
			$size = length($response);
			print "received: $size\n";
		} else {
			print "Socket recv() error. Did remote close it on me?\n";
			print "Better fail the channel!\n";
			exit();
		}
		
		# Server is kluged to never send message lengths divisible by 1024. 
		if (length($response) < 1024) {
			last;
		}
	}
	
	sleep 2;
}

$socket->close();
