use 5.20.0;
use warnings;
use experimental qw(lexical_subs signatures postderef);

package Bakesale::Test {
  use File::Temp qw(tempdir);

  sub new_test_app_and_tester {
    require JMAP::Tester;
    require Plack::Test;

    my $conn_info = Bakesale::Test->test_schema_connect_info;

    my $app = Bakesale::App->new({ connect_info => $conn_info });

    my $plack_test = Plack::Test->create($app->to_app);

    my $jmap_tester = JMAP::Tester->new({
      jmap_uri => 'https://localhost/jmap',
      _request_callback => sub {
        shift; $plack_test->request(@_);
      },
    });

    return ($app, $jmap_tester);
  }

  sub test_schema_connect_info {
    my $dir = tempdir(CLEANUP => 1);

    require Bakesale::Schema;
    my @connect_info = (
      "dbi:SQLite:dbname=$dir/bakesale.sqlite",
      undef,
      undef,
      { quote_names => 1 },
    );
    my $schema = Bakesale::Schema->connect(@connect_info);

    $schema->deploy;

    return \@connect_info;
  }

  sub load_trivial_dataset ($self, $connect_info) {
    my $schema = Bakesale::Schema->connect(@$connect_info);

    my sub modseq ($x) { return (modSeqCreated => $x, modSeqChanged => $x) }

    $schema->resultset('Cookie')->populate([
      { accountId => 1, modseq(1), id => 1, type => 'tim tam',
        baked_at => '2016-01-01T12:34:56Z' },
      { accountId => 1, modseq(1), id => 2, type => 'oreo',
        baked_at => '2016-01-02T23:45:60Z' },
      { accountId => 2, modseq(1), id => 3, type => 'thin mint',
        baked_at => '2016-01-23T01:02:03Z' },
      { accountId => 1, modseq(3), id => 4, type => 'samoa',
        baked_at => '2016-02-01T12:00:01Z' },
      { accountId => 1, modseq(8), id => 5, type => 'tim tam',
        baked_at => '2016-02-09T09:09:09Z' },
    ]);

    $schema->resultset('CakeRecipe')->populate([
      { accountId => 1, modseq(1),
        id => 1, type => 'seven-layer', avg_review => 91 },
    ]);

    $schema->resultset('State')->populate([
      { accountId => 1, type => 'cookies', lowestModSeq => 1, highestModSeq => 8 },
      { accountId => 2, type => 'cookies', lowestModSeq => 1, highestModSeq => 1 },
    ]);

    return;
  }
}

package Bakesale {
  use Moose;
  with 'Ix::Processor::WithSchema';

  use Ix::Util qw(error result);

  use experimental qw(signatures postderef);
  use namespace::autoclean;

  sub schema_class { 'Bakesale::Schema' }

  sub handler_for ($self, $method) {
    return 'pie_type_list' if $method eq 'pieTypes';
    return 'bake_pies'     if $method eq 'bakePies';
    return;
  }

  sub pie_type_list ($self, $ctx, $arg = {}) {
    my $only_tasty = delete local $arg->{tasty};
    return error('invalidArguments') if keys %$arg;

    my @flavors = qw(pumpkin apple pecan);
    push @flavors, qw(cherry eel) unless $only_tasty;

    return Bakesale::PieTypes->new({ flavors => \@flavors });
  }

  sub bake_pies ($self, $ctx, $arg = {}) {
    return error("invalidArguments")
      unless $arg->{pieTypes} && $arg->{pieTypes}->@*;

    my %is_flavor = map {; $_ => 1 }
                    $self->pie_type_list($ctx, { tasty => $arg->{tasty} })->flavors;

    my @rv;
    for my $type ($arg->{pieTypes}->@*) {
      if ($is_flavor{$type}) {
        push @rv, Bakesale::Pie->new({ flavor => $type });
      } else {
        push @rv, error(noRecipe => { requestedPie => $type })
      }
    }

    return @rv;
  }

  __PACKAGE__->meta->make_immutable;
  1;
}

package Bakesale::PieTypes {
  use Moose;
  with 'Ix::Result';

  use experimental qw(signatures postderef);
  use namespace::autoclean;

  has flavors => (
    traits   => [ 'Array' ],
    handles  => { flavors => 'elements' },
    required => 1,
  );

  sub result_type { 'pieTypes' }

  sub result_properties ($self) {
    return {
      flavors => [ $self->flavors ],
    };
  }

  __PACKAGE__->meta->make_immutable;
  1;
}

package Bakesale::Pie {
  use Moose;

  with 'Ix::Result';

  use experimental qw(signatures postderef);
  use namespace::autoclean;

  has flavor     => (is => 'ro', required => 1);
  has bake_order => (is => 'ro', default => sub { state $i; ++$i });

  sub result_type { 'pie' }
  sub result_properties ($self) {
    return { flavor => $self->flavor, bakeOrder => $self->bake_order };
  }
}

1;
