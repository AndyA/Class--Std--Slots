use Test::More tests => 1;

package T::Class::One;
use base qw(Class::Std::Slots);

sigs(qw(
    my_signal
));

sub my_slot :slot {
    print "My slot\n";
}

package T::Class::Two;
use base qw(Class::Std::Slots);

sigs(qw(
    another_signal;
));

sub another_slot :slot {
    print "Another slot\n";
}

package main;
ok(1, 'Always passes');
