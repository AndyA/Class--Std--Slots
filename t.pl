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
        warn "Build T::Class::Two\n";
    }

    sub DEMOLISH {
        warn "DEMOLISH T::Class::Two\n";
    }

    sub another_slot {
        my $self = shift;
        warn $self . '->another_slot(', join(', ', @_), ")\n";
        $self->another_signal($self);
    }
}

package main;

my $ob2 = T::Class::Two->new();
my $ob1 = T::Class::One->new();

$ob1->connect('my_signal', $ob2, 'another_slot', { reveal_source => 1 });
$ob2->connect('another_signal', $ob1, 'my_slot');
$ob2->connect('another_signal', $ob1, 'my_second_slot');

# Install an anon slot
$ob2->connect('another_signal', sub { print "Boo!\n"; });

$ob1->my_signal('Wow!');
