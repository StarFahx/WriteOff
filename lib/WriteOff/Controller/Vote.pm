package WriteOff::Controller::Vote;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

WriteOff::Controller::Vote - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub prelim :PathPart('vote/prelim') :Chained('/event/fic') :Args(0) {
	my ( $self, $c ) = @_;
	my $e = $c->stash->{event};

	$c->detach('/error', [ "There is no preliminary voting round for this event." ])
		unless $e->prelim;

	if ($c->user) {
		$c->stash->{records} = $e->vote_records->search({
			filled  => 0,
			round   => 'prelim',
			type    => 'fic',
			user_id => $c->user->get('id'),
		});

		if ($c->req->method eq 'POST' && $e->prelim_votes_allowed) {
			if (!$c->stash->{records}->count) {
				my $err = $e->new_prelim_record_for(
					$c->user, $c->config->{prelim_distr_size}
				);

				$c->stash->{error_msg} = $err if $err;
			}
			else {
				$c->stash->{error_msg} = "You have empty records to fill in";
			}
		}
	}

	$c->stash(
		votes_received => $e->vote_records->prelim->filled->count,
	);

	push $c->stash->{title}, 'Vote', 'Prelim';
	$c->stash->{template} = 'vote/prelim.tt';
}

sub private :PathPart('vote/private') :Chained('/event/fic') :Args(0) {
	my ( $self, $c ) = @_;
	my $e = $c->stash->{event};

	$c->detach('/error', [ "There is no private judging for this event." ])
		unless $e->private;

	$c->stash->{finalists} = $e->storys->search(
		{ finalist => 1 },
		{ order_by => 'title' },
	);

	$c->stash(
		judge => $e->judges->find($c->user_id),
		votes_received => $e->vote_records->private->filled->count,
	);

	$c->stash->{records} = $e->vote_records->unfilled->search({
		round    => 'private',
		type     => 'fic',
		user_id  => $c->stash->{judge}->id,
	})->unfilled if $c->stash->{judge};

	push $c->stash->{title}, 'Vote', 'Private';
	$c->stash->{template} = 'vote/private.tt';
}

=head1 AUTHOR

Cameron Thornton E<lt>cthor@cpan.orgE<gt>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
