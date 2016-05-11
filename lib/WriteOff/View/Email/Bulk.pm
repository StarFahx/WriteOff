use utf8;
package WriteOff::View::Email::Bulk;

use strict;
use warnings;
use base 'Catalyst::View';

use Email::MIME;
use Email::Sender::Simple ();
use Text::Wrap ();

sub process {
	my ($self, $c) = @_;

	$c->stash->{bulk} = 1;
	$c->stash->{subject} = $c->stash->{email}{subject} // 'No subject';

	my $html = $c->view('TT')->render($c, $c->stash->{email}{template});
	$c->stash->{wrapper} = 'wrapper/none.tt';
	my $plain = $c->view('TT')->render($c, $c->stash->{email}{template});

	if (!$html || !$plain) {
		die 'Failed to render template: ' . $c->stash->{email}{template} . "\n";
	}

	for ($html, $plain) {
		# Trim comments and trailing space from email body
		s/<!--.+?-->//gs;
		s/^\s+|\s+$//g;
	}

	# Re-wrap paragraphs (templates are wrapped, but output won't line up properly)
	$plain =~ s/(?<!\n)\n(?!\n)/ /g;
	$plain = Text::Wrap::wrap("", "", $plain);

	my $email = Email::MIME->create(
		header => [
			From    => $c->mailfrom,
			Subject => $c->stash->{subject},
		],
		parts => [
			Email::MIME->create(
				body => $plain,
				content_type => 'text/plain',
				encoding => 'utf-8',
			),
			Email::MIME->create(
				body => $html,
				content_type => 'text/html',
				charset => 'utf-8',
			),
		],
	);

	for my $user ($c->stash->{email}{users}->all) {
		$email->header_set(To => sprintf "%s <%s>", $user->name, $user->email);
		Email::Sender::Simple->send($email);
	}
}

1;
