package WriteOff::Controller::Vote;
use Moose;
use namespace::autoclean;
use Scalar::Util qw/looks_like_number/;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

WriteOff::Controller::Vote - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub cast :Private {
	my ($self, $c) = @_;

	if ($c->stash->{round} && $c->stash->{candidates}->count && $c->user) {
		my $records = $c->stash->{event}->vote_records->search({
			user_id => $c->user->id,
			type    => $c->stash->{type},
		});

		my $record = $records->search({ round => $c->stash->{round} })->first;

		if (!$record) {
			$record = $c->stash->{event}->create_related('vote_records', {
				abstains => 3,
				user_id => $c->user->id,
				round => $c->stash->{round},
				type  => $c->stash->{type},
			});
		}

		$c->stash->{pool} = $c->stash->{candidates}->search({
			id => { -not_in => $record->votes->get_column('story_id')->as_query },
			user_id => { '!=' => $c->user->id },
		});

		if (!$record->votes->count) {
			# Copy previous votes to the ballot
			if (my $prev = $records->search({ round => $c->stash->{prev} })->first) {
				for my $vote ($prev->votes) {
					if ($c->stash->{candidates}->search({ id => $vote->story_id })->count) {
						$record->create_related('votes', {
							story_id => $vote->story_id,
							value => $vote->value,
						});
					}
				}
			}

			# Assign some stories to the ballot
			my $mins = $c->stash->{countdown}->delta_ms($c->stash->{now})->in_units('minutes');
			my $w = $mins / 1440 * $c->config->{work}{threshold} * $c->config->{work}{voter};

			for my $story ($c->stash->{pool}->all) {
				$story->create_related('votes', { record_id => $record->id });
				$w -= $c->config->{work}{offset} + $story->wordcount / $c->config->{work}{rate};
				last if $w < 0;
			}
		}

		$c->stash->{record} = $record;
		$c->stash->{ordered} = $record->votes->ordered;
		$c->stash->{unordered} = $record->votes->search({ value => undef, abstained => 0 });
		$c->stash->{abstained} = $record->votes->search({ abstained => 1 });
	}

	push $c->stash->{title}, $c->stash->{label} || 'Vote';
	$c->stash->{template} = 'vote/cast.tt';

	$c->forward('do_cast') if $c->req->method eq 'POST';
}

sub do_cast :Private {
	my ($self, $c) = @_;

	my $record = $c->stash->{record};
	return unless $record;

	my $action = $c->req->params->{action} // 'reorder';
	if ($action eq 'abstain' || $action eq 'unabstain') {
		my $id = $c->req->params->{vote};
		return unless looks_like_number $id;

		my $vote = $record->votes->find($id);
		$c->detach('/error', [ 'Vote not found' ]) unless $vote;

		if ($action eq 'abstain') {
			return if $vote->abstained || $record->abstains <= 0;

			$vote->update({ abstained => 1, value => undef });
			$record->update({ abstains => $record->abstains - 1 });
			$c->res->body($record->abstains);
		}
		elsif ($action eq 'unabstain') {
			return if !$vote->abstained;

			$vote->update({ abstained => 0 });
			$record->update({ abstains => $record->abstains + 1 });
			$c->res->body($record->abstains);
		}
	}
	elsif ($action eq 'append') {
		$c->detach('/error', [ 'You have candidates remaining' ]) if $c->stash->{unordered}->count;

		if (!$c->stash->{pool}->count) {
			$c->res->body('None left');
		}
		else {
			my $tail = $c->stash->{pool}->first;
			$c->stash->{vote} = $tail->create_related('votes', { record_id => $record->id });
			$c->stash->{score} = 'N/A';
			$c->stash->{template} = 'vote/ballot-item.tt';
		}
	}
	elsif ($action eq 'reorder') {
		my $votes = $record->votes;
		my %okay = map { $_->id => 1 } $votes->search({ abstained => 0 });
		my @order = grep { defined && $okay{$_} } $c->req->param("order"), $c->req->param("order[]");

		$votes->update({ value => undef });
		while (@order) {
			$votes->find(shift @order)->update({ value => scalar @order });
		}
	}
}

sub fic :PathPart('vote') :Chained('/event/fic') :Args(0) {
	my ($self, $c) = @_;

	my $e = $c->stash->{event};

	$c->stash->{type} = 'fic';
	$c->stash->{view} = $c->controller('Fic')->action_for('view');

	if ($e->prelim_votes_allowed) {
		$c->stash->{round} = 'prelim';
		$c->stash->{label} = 'Prelims';
		$c->stash->{countdown} = $e->public;
		$c->stash->{candidates} = $e->storys->eligible->sample;
	} elsif ($e->public_votes_allowed) {
		$c->stash->{prev} = 'prelim';
		$c->stash->{round} = 'public';
		$c->stash->{label} = $e->public_label;
		$c->stash->{countdown} = $e->private || $e->end;
		$c->stash->{candidates} = $e->storys->candidates->sample;
	} elsif ($e->private_votes_allowed) {
		$c->stash->{prev} = 'prelim';
		$c->stash->{round} = 'private';
		$c->stash->{label} = 'Finals';
		$c->stash->{countdown} = $e->end;
		$c->stash->{candidates} = $e->storys->finalists->sample;
	} elsif (!$e->ended) {
		$c->stash->{countdown} = $e->prelim || $e->public || $e->private;
	}

	$c->forward('cast');
}

=head1 AUTHOR

Cameron Thornton E<lt>cthor@cpan.orgE<gt>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
