use utf8;
package WriteOff::Schema::Result::Schedule;

use strict;
use warnings;
use base "WriteOff::Schema::Result";

__PACKAGE__->table("schedules");

__PACKAGE__->add_columns(
	"id",
	{ data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
	"format_id",
	{ data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
	"genre_id",
	{ data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
	"next",
	{ data_type => "timestamp", is_nullable => 0 },
	"period",
	{ data_type => "integer", is_nullable => 0 },
);

__PACKAGE__->set_primary_key("id");

__PACKAGE__->belongs_to("format", "WriteOff::Schema::Result::Format", "format_id");
__PACKAGE__->belongs_to("genre", "WriteOff::Schema::Result::Genre", "genre_id");

1;
