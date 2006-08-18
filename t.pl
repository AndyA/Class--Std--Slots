#!/usr/bin/perl -w

use strict;
use lib qw(lib);

package T::Class::One;
use Class::Std;
use Class::Std::Slots;
{
    signals qw(
        my_signal
    );

    sub BUILD {
        warn "BUILD T::Class::One\n";
    }

    sub DEMOLISH {
        warn "DEMOLISH T::Class::One\n";
    }

    sub my_slot {
        my $self = shift;
        warn $self . '->my_slot(', join(', ', @_), ")\n";
    }

    sub my_second_slot {
        my $self = shift;
        warn $self . '->my_second_slot(', join(', ', @_), ")\n";
    }
}

package T::Class::Two;
use Class::Std;
use Class::Std::Slots;
{
    signals qw(
        another_signal
    );

    sub BUILD {
        warn "BUILD T::Class::Two\n";
    }

    sub DEMOLISH {
        warn "DEMOLISH T::Class::Two\n";
    }

    sub another_slot {
        my $self = shift;
        warn $self . '->another_slot(', join(', ', @_), ")\n";
        $self->another_signal(@_);  # Trigger another signal
    }
}

package T::Class::Two::More;
use base qw(T::Class::Two);
use Class::Std;
use Class::Std::Slots;
{
    signals qw(
        more_signal
    );

    sub BUILD {
        warn "BUILD T::Class::Two::More\n";
    }

    sub DEMOLISH {
        warn "DEMOLISH T::Class::Two::More\n";
    }

    sub more_slot {
        my $self = shift;
        warn $self . '->more_slot(', join(', ', @_), ")\n";
    }
}

package main;

my $ob1 = T::Class::One->new();
my $ob2 = T::Class::Two->new();
my $ob3 = T::Class::Two::More->new();

$ob1->connect('my_signal',      $ob2, 'another_slot', { reveal_source => 1 });
$ob2->connect('another_signal', $ob1, 'my_slot');
$ob2->connect('another_signal', $ob1, 'my_second_slot');

# Connect up the third object
$ob3->connect('more_signal',    $ob1, 'my_slot');
$ob2->connect('another_signal', $ob3, 'more_slot');

# Install an anon slot
$ob2->connect('another_signal', sub {
    my $src = shift;
    print "Got $src->{signal}\n";
    for (keys %{$src}) {
        print "    $_ => $src->{$_}\n";
    }
}, { reveal_source => 1 });

$ob1->my_signal('Wow!');
$ob3->more_signal('More!');

$ob2->disconnect('another_signal', $ob1, 'my_slot');
#$ob2->disconnect('another_signal', $ob1);

#$ob1->connect('my_signal', $ob2, 'frobnicate');

$ob1->my_signal('Whoop!');
