package WriteOff::View::HTML;
use utf8;
use Moose;
use namespace::autoclean;
use Template::Stash;
use Template::Filters;
use Parse::BBCode;
use Text::Markdown;
use WriteOff::Helpers;
require DateTime::Format::Human::Duration;

extends 'Catalyst::View::TT';

__PACKAGE__->config(
	WRAPPER            => 'wrapper.tt',
	ENCODING           => 'utf-8',
	TEMPLATE_EXTENSION => '.tt',
	TIMER              => 1,
	FILTERS => {
		markdown => sub {
			my $text = shift;
			$text = Text::Markdown->new->markdown($text);

			# Add classes to bare links (e.g., those generated by markdown)
			$text =~ s`<a (href=".+?")>`<a $1 class="link new-tab">`g;

			return $text;
		},
		simple_uri => \&WriteOff::Helpers::simple_uri,
	},
	expose_methods => [ qw/format_dt bb_render medal_for title_html/ ],
	render_die     => 1,
);

$Template::Stash::SCALAR_OPS->{ucfirst} = sub {
	return ucfirst shift;
};

$Template::Stash::LIST_OPS->{join_serial} = sub {
	my @list = @{+shift};
	
	return join ", ", @list if $#list < 2;
	
	my $last = pop @list;
	$list[-1] .= ", and $last";
	
	return join ", ", @list;
};

$Template::Stash::LIST_OPS->{join_en} = sub {
	join " – ", @{$_[0]};
};

$Template::Stash::LIST_OPS->{sort_stdev} = sub {
	return [ sort { $b->stdev <=> $a->stdev } @{ $_[0] } ]
};

$Template::Stash::LIST_OPS->{map_username} = sub {
	return [ map { $_->username } @{ $_[0] } ];
};

my $RFC2822 = '%a, %d %b %Y %T %Z';

sub format_dt {
	my( $self, $c, $dt, $fmt ) = @_;
	
	return '' unless eval { $dt->set_time_zone('UTC')->isa('DateTime') };
	
	my $tz = $c->user ? $c->user->get('timezone') : 'UTC';
	
	return sprintf '<time title="%s" datetime="%sZ">%s</time>',
	$dt->strftime($RFC2822), 
	$dt->iso8601, 
	$dt->set_time_zone($tz)->strftime($fmt // $RFC2822);
}

sub title_html {
	my( $self, $c ) = @_;
	
	my $title = $c->stash->{title};
	
	return 
		join " – ",
		map { Template::Filters::html_filter($_) } 
		ref $title eq 'ARRAY' ? reverse @$title : $title || ();
}

my $bb = Parse::BBCode->new({
	tags => {
		b => '<strong>%{parse}s</strong>',
		i => '<em>%{parse}s</em>',
		u => '<span style="text-decoration: underline">%{parse}s</span>',
		s => '<del>%{parse}s</del>',
		url => '<a class="link new-tab" href="%{link}a">%{parse}s</a>',
		size => '<span style="font-size: %{size}aem;">%{parse}s</span>',
		color => '<span style="color: %{color}a;">%{parse}s</span>',
		smcaps => '<span style="font-variant: small-caps">%{parse}s</span>',
		center => {
			class => 'block',
			output => '<div style="text-align: center">%{parse}s</div>',
		},
		quote => {
			class => 'block',
			output => '<blockquote>%{parse}s</blockquote>',
		},
		hr => {
			class => 'block',
			output => '<hr>',
			single => 1,
		},
	},
	escapes => {
		Parse::BBCode::HTML->default_escapes,
		size => sub {
			$_[2] !~ /\D/ && 
			8 <= $_[2] && $_[2] <= 72 ? 
			$_[2] / 16 : 1;
		},
		color => sub {
			$_[2] =~ /\A#?[0-9a-zA-Z]+\z/ ? $_[2] : 'inherit';
		},
	},
});

sub bb_render {
	my ( $self, $c, $text ) = @_;
	
	return '' unless $text;
	
	$text = $bb->render( $text );

	# Remove line breaks that immediately follow blocks
	for my $block ( '<hr>', '</blockquote>', '</div>' ) {
		my $e = quotemeta $block;
		$text =~ s/$e\K\s*?<br>//g;
	}
	
	return $text;
}

sub medal_for {
	my( $self, $c, $pos ) = @_;
	
	return $c->model('DB::Award')->medal_for( $pos );
}

package DateTime;

my $RFC2822 = '%a, %d %b %Y %T %Z';

sub duration_since_now {
	my $self = shift;

	return sprintf '<time title="%s" datetime="%sZ">%s</time>',
		$self->set_time_zone('UTC')->strftime($RFC2822), 
		$self->iso8601, 
		DateTime::Format::Human::Duration->new->format_duration_between(
			DateTime->now,
			$self,
			past => '%s ago',
			future => 'in %s',
			no_time => 'just now',
			significant_units => 2,
		);
}

1;
