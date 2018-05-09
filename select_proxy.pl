use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;

# auto-flush on socket
$| = 1;

my $listen_port = $ARGV[0];
my $server_ip   = $ARGV[1];
my $server_port = $ARGV[2];

print("Listening on 127.0.0.1 port $listen_port.\n");
print("Redirecting connections to $server_ip:$server_port.\n");

# creating a listening socket
my $listen_socket = new IO::Socket::INET (
	LocalHost => '127.0.0.1',
	LocalPort => $listen_port,
	Proto => 'tcp',
	Listen => 5,
	Reuse => 1
);
die "Cannot create proxy socket $!\n" unless $listen_socket;
print "Proxy server waiting for client connection on port $listen_port\n";

my $client_socket;
my $server_socket;

my $socket_set = new IO::Select();
$socket_set->add($listen_socket);

SELECT: while(1) {

	my ($ready_set) = IO::Select->select($socket_set, undef, undef, 0.25);

	foreach my $r (@$ready_set) {

		if ($r == $listen_socket) {
			# If we already have one, dump it for the new one.
			if ($client_socket) {
				shutdown($client_socket, 1);
				$client_socket->close();
				$socket_set->remove($client_socket);
				undef($client_socket);
			}

			$client_socket = $listen_socket->accept();
			$socket_set->add($client_socket);
		}

		if (defined($client_socket) && $r == $client_socket) {

			my $data = "";
			my $size = $client_socket->recv($data, 10240);

			if ($size) {
				my $rsize = length($data);
				print "Received $rsize from client.\n";

				my $server_socket_retries = 10;

				while (! $server_socket) {
					# Send request to real server which closes connections:
					# Create a connecting socket to real server:
					$server_socket = new IO::Socket::INET (
					    PeerHost => $server_ip,
					    PeerPort => $server_port,
					    Proto => 'tcp',
					);
					unless ($server_socket) {
						print "Cannot connect to the real server: $!\n";

						$server_socket_retries--;
						unless ($server_socket_retries > 0) {

							print "Exhausted retries connecting to server.\n";

							# Close client.
							shutdown($client_socket, 1);
							$client_socket->close();
							$socket_set->remove($client_socket);
							undef($client_socket);

							# Go back to select.
							next SELECT;
						}
					} else {
						$socket_set->add($server_socket);
						print "Connected to the real server.\n";
					}
				}

				$size = $server_socket->send($data);
				if ($size) {
					print "Sent $size to server.\n";
				} else {
					print "Server socket send() error. Did server close it on me? We just made sure this was open!\n";
				}


			} else {
				print "Client socket recv() error. Did remote close it on me?\n";
				print "Close client socket and wait for new connection.\n";
				shutdown($client_socket, 1);
				$client_socket->close();
				$socket_set->remove($client_socket);
				undef($client_socket);
			}

		}

		if (defined($server_socket) && ($r == $server_socket)) {

			my $data = "";
			my $size = $server_socket->recv($data, 10240);

			if ($size && $data && $client_socket) {
				my $rsize = length($data);
				print "received $rsize from server.\n";

				#Write it to client.
				$size = $client_socket->send($data);
				if ($size) {
					print "Sent $size to client.\n";
				} else {
					print "Client socket send() error. Did client close it on me?\n";
					print "Close client socket and wait for new connection.\n";
					shutdown($client_socket, 1);
					$client_socket->close();
					$socket_set->remove($client_socket);
					undef($client_socket);
				}

			} else {
				print ("Closing server socket.\n");
				shutdown($server_socket, 1);
				$server_socket->close();
				$socket_set->remove($server_socket);
				undef($server_socket);
			}
		}
	}
}

$listen_socket->close();
