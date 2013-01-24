#!/opt/local/bin/perl

################################################
# Dependencies
################################################

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Net::OAuth;
use LWP;
use URI;
use JSON;
use Encode qw(decode);

################################################
# Command Line Parameters
################################################

# boolean
my $opt_man    = 0;
my $opt_help   = 0;
my $opt_nosend = 0;
my $opt_force  = 0;

# string
my $opt_uri           = 'http://example.com/web/api';
my $opt_api           = '/message';
my $opt_method        = 'POST';
my $opt_protocol      = 'HTTP/1.1';
my $opt_content_type  = 'application/json';
my $opt_charset       = 'utf-8';
my $opt_oauth_version = '1.0';
my $opt_key           = 'ABCDEFGH12345678';
my $opt_secret        = 'ABCDEFGHIJKLMNOP1234567890123456';
my $opt_requestor     = '12345678';
my $opt_app_id        = '12345678';

# integer
my $opt_max_recipients = 10;
my $opt_max_title      = 30;
my $opt_max_body       = 300;

# message data
my $opt_title      = "Title";
my $opt_body       = "Body";
my @opt_recipients = (
);

# process command line arguments
my $result = GetOptions (
  "title|t=s"         => \$opt_title,
  "body|b=s"          => \$opt_body,
  "recipients|r=s{,}" => \@opt_recipients,
  "max-recipients=i"  => \$opt_max_recipients,
  "uri=s"             => \$opt_uri,
  "api=s"             => \$opt_api,
  "method=s"          => \$opt_method,
  "protocol=s"        => \$opt_protocol,
  "content-type=s"    => \$opt_content_type,
  "charset=s"         => \$opt_charset,
  "oauth-version=s"   => \$opt_oauth_version,
  "key=s"             => \$opt_key,
  "secret=s"          => \$opt_secret,
  "requestor=s"       => \$opt_requestor,
  "app-id=s"          => \$opt_app_id,
  "max-title=i"       => \$opt_max_title,
  "max-body=i"        => \$opt_max_body,
  "nosend|n"          => sub { $opt_nosend  = 1; },
  "force|f"           => sub { $opt_force   = 1; },
  "man"               => \$opt_man,
  "help|?"            => \$opt_help,
) or pod2usage ( 2 );

# print help
pod2usage ( 1 ) if $opt_help;
pod2usage ( -exitstatus => 0, -verbose => 2 ) if $opt_man;

# default recipients
if ( scalar @opt_recipients < 1 ) {
  @opt_recipients = ( 1 .. $opt_max_recipients + 1 );
}

################################################
# Send Message
################################################

my $uri = buildURI ( $opt_uri, $opt_api );
sendMultiMessage (
  $opt_method,
  $uri,
  $opt_title,
  $opt_body,
  \@opt_recipients
);

################################################
# OAuth Authorization Header
################################################

sub buildOAuthAuthorizationHeader {
  # Values from Command Line
  my $oauth_version = $opt_oauth_version;
  my $uri           = buildURI ( $opt_uri, $opt_api );

  # Dynamic Nonce Values
  my $oauth_nonce     = nonce();
  my $oauth_timestamp = time;

  # Fixed Values
  my $oauth_signature_method = 'HMAC-SHA1';

  # Request
  my $oauth_request = Net::OAuth->request ( 'consumer' ) ->new (
    request_method   => $opt_method,
    request_url      => $uri,

    consumer_key     => $opt_key,
    consumer_secret  => $opt_secret,
    nonce            => $oauth_nonce,
    signature_method => $oauth_signature_method,
    timestamp        => $oauth_timestamp,
    version          => $oauth_version,

    extra_params => {
      'user_app_id'         => $opt_app_id,
      'xoauth_requestor_id' => $opt_requestor,
    },
  );
  $oauth_request->sign;

  # Authorization Header
  my $oauth_authorization_header = $oauth_request->to_authorization_header;
  $oauth_authorization_header .= ",app_id=\"$opt_app_id\"";
  $oauth_authorization_header .= ",xoauth_requestor_id=\"$opt_requestor\"";
  return $oauth_authorization_header;
}

################################################
# Build URI
################################################

sub buildURI {
  my ( $uri_base, $uri_api ) = @_;
  my $uri = $uri_base . $uri_api;
  return $uri;
}

################################################
# Prepare Message Data
################################################

sub prepareData {
  my ( $title, $body, @recipients ) = @_;
  my %data = (
    "title"      => $title,
    "body"       => $body,
    "recipients" => @recipients
  );
  verifyData ( %data );
  my $result = encodeData ( %data );
  return $result;
}

################################################
# Verify Message Data
################################################

sub verifyData {
  my $do_not_die       = $opt_force || $opt_nosend ;
  my $error            = 0;

  my %data         = @_;
  my $title        = $data { title };
  my $title_length = stringLength ( $title );
  my $body         = $data { body  };
  my $body_length  = stringLength ( $body );

  if ( $opt_max_title < $title_length ) {
    print "ERROR:    Message title too long, $title_length characters.";
    print "  Max length $opt_max_title characters.\n";
    $error = 1;
  }
  if ( $opt_max_body < $body_length ) {
    print "ERROR:    Message body too long, $body_length characters.";
    print "  Max length $opt_max_body characters.\n";
    $error = 1;
  }
  if ( $error ) {
    die   "ERROR:    Abort.  Message can not be sent." unless $do_not_die;
    print "WARNING:  Forcing message to send.\n"       if     $opt_force;
    printBreak();
  }
}

################################################
# Encode Message Data
################################################

sub encodeData {
  my %data   = @_;
  my $result = JSON->new->utf8 ( 0 ) ->encode ( \%data );
  return $result;
}

################################################
# Send Multiple Messages
################################################

sub sendMultiMessage {
  printBreak();
  my (
    $opt_method,
    $uri,
    $opt_title,
    $opt_body,
    $data_recipients_reference
  ) = @_;
  my $iterator = natatime (
    $opt_max_recipients,
    @ { $data_recipients_reference }
  );
  while ( my @recipient_subset = $iterator->() ) {
    my $body = prepareData ( $opt_title, $opt_body, \@recipient_subset );
    sendMessage ( $opt_method, $uri, $body );
  }
}

################################################
# Send Single Message
################################################

sub sendMessage {
  # parameters
  my ( $opt_method, $uri, $body ) = @_;

  # oauth authorization header
  my $oauth_authorization_header = buildOAuthAuthorizationHeader();

  # request
  my $request = HTTP::Request->new( $opt_method, $uri );
  $request->header   ( 'Content-Type'  => $opt_content_type );
  $request->header   ( 'charset'       => $opt_charset );
  $request->header   ( 'Authorization' => $oauth_authorization_header );
  $request->protocol ( $opt_protocol );
  $request->content  ( $body );

  # output
  print "Sending Message ... \n\n" unless $opt_nosend;
  print $request->as_string;
  print "\n"                       unless $opt_nosend;

  # response
  unless ( $opt_nosend ) {
    my $browser  = LWP::UserAgent->new;
    my $response = $browser->request( $request );
    if ( not $response->is_success ) {
      print "ERROR:    ", $response->status_line, " @ $uri\n";
    }
    print "RESPONSE: ", $response->content, "\n";
  }
  printBreak();
}

################################################
# Print Break in Output
################################################

sub printBreak {
  print "\n---\n\n";
}

################################################
# Generate Nonce
################################################

sub nonce {
  my @a = ('A'..'Z', 'a'..'z', 0..9);
  my $nonce = '';
  for(0..31) {
    $nonce .= $a[rand(scalar(@a))];
  }
  return $nonce;
}

################################################
# Get N Items at a Time
################################################

sub natatime ( $@ ) {
  my $n = shift;
  my @list = @_;

  return sub
  {
    return splice @list, 0, $n;
  }
}

################################################
# Custom String Length Function
################################################

# this function is probably broken
sub stringLength ( $@ ) {
  my $text = shift;

  my $c_text = $text;
  my $length = length(decode('utf-8', $c_text));
  return $length;
}

################################################
# Documentation
################################################

__END__

=head1 NAME

oauth-api-example - Send a message to a web API.

=head1 SYNOPSIS

oauth-api-example [options]

 Options:
   --title          specify message title
   -t               specify message title
   --body           specify message body
   -b               specify message body
   --recipients     specify list of recipients
   -r               specify list of recipients
   --uri            specify web API base URI
   --api            specify web API call
   --method         specify request method
   --protocol       specify http protocol
   --content-type   specify content type
   --charset        specify charset
   --oauth-version  specify OAuth version
   --key            specify consumer key
   --secret         specify consumer secret
   --requestor      specify requestor
   --app-id         specify app ID
   --max-recipients specify maximum number of recipients per message
   --max-title      specify maximum title length
   --max-body       specify maximum body length
   --nosend         do not send message request to API server
   -n               do not send message request to API server
   --force          force send message request to API server
   -f               force send message request to API server
   --help           brief help message
   -?               brief help message
   --man            full documentation

=head1 OPTIONS

=over 8

=item B<--title>

Specify the message title.

=item B<-t>

Specify the message title.

=item B<--body>

Specify the message body.

=item B<-b>

Specify the message body.

=item B<--recipients>

Specify the list of recipients.

=item B<-r>

Specify the list of recipients.

=item B<--uri>

Specify the web API base URI.

=item B<--api>

Specify the web API call.  Unnecessary unless the
endpoint is changed.

=item B<--method>

Specify the request method.  Defautls to POST.

=item B<--protocol>

Specify the http protocol.

=item B<--content-type>

Specify the content type.

=item B<--charset>

Specify the charset.

=item B<--oauth-version>

Specify the OAuth version.

=item B<--key>

Specify the consumer key.

=item B<--secret>

Specify the consumer secret.

=item B<--requestor>

Specify the requestor.

=item B<--app-id>

Specify the app ID.

=item B<--max-recipients>

Specify the maximum number of recipients per message.

=item B<--max-title>

Specify the maximum message title length.

=item B<--max-body>

Specify the maximum message body length.

=item B<--nosend>

Do not send a message request to API server.  The request that
would be sent will be printed.  Useful for testing.

=item B<-n>

Do not send a message request to API server.  The request that
would be sent will be printed.  Useful for testing.

=item B<--force>

Force a message request to be sent to the API server.  Validity
check will be performed, but the message will still be sent if
they fail.

=item B<-f>

Force a message request to be sent to the API server.  Validity
check will be performed, but the message will still be sent if
they fail.

=item B<--help>

Print a brief help message and exits.

=item B<-?>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<This program> will send a message to the indicated recipients
via the DMM web API.

=cut
