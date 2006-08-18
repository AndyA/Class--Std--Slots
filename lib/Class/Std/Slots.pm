package Class::Std::Slots;

use warnings;
use strict;
use Carp;
use Scalar::Util qw(blessed refaddr weaken);

use version; our $VERSION = qv('0.0.1');

my %signal_map  = ( );  # maps id -> signame -> array of connected slots
my %signal_busy = ( );  # maps id -> signame -> busy flag

# Subs we export to caller's namespace
my @exported_subs = qw(
    connect
    disconnect
    signals
);

sub _validate_signal_name {
    my $sig_name = shift;
    croak "Invalid signal name '$sig_name'"
        unless $sig_name =~ /^\w(?:[\w\d])*$/;
}

sub _check_signal_exists {
    my $class    = shift;
    my $sig_name = shift;
    _validate_signal_name($sig_name);
    croak "Signal '$sig_name' undefined"
        unless UNIVERSAL::can($class, $sig_name);
}

sub _emit_signal {
    my $self     = shift;
    my $sig_name = shift;
    my $src_id   = refaddr($self);

    unless (blessed($self)) {
        croak "Signal '$sig_name' must be invoked as a method\n";
    }

    if (exists($signal_busy{$src_id}->{$sig_name})) {
        croak "Attempt to re-enter signal '$sig_name'";
    }

    # Flag this signal as busy
    $signal_busy{$src_id}->{$sig_name}++;

    # We still want to remove the busy lock on the signal
    # even if one of the slots dies - so wrap the whole
    # thing in an eval.
    eval {
        # Get the slots registered with this signal
        my $slots = $signal_map{$src_id}->{$sig_name};

        # Might have none... It's not an error.
        if (defined $slots) {
            for my $slot (@{$slots}) {
                my ($dst_obj, $dst_method, $options) = @{$slot};
                if (defined($dst_obj)) {

                    my @args = @_;

                    # The reveal_source option causes a hashref
                    # describing the source of the signal to
                    # be prepended to the args.
                    if ($options->{reveal_source}) {
                        unshift @args, {
                            source  => $self,
                            signal  => $sig_name,
                            options => $options
                        };
                    }

                    # Call an anon sub or a method
                    if (blessed($dst_obj)) {
                        $dst_obj->$dst_method(@args);
                    }
                    else {
                        $dst_obj->(@args);
                    }
                }
            }
        }
    };

    # Remove busy flag
    delete $signal_busy{$src_id}->{$sig_name};

    die if $@;
}

sub _connect_usage {
    croak 'Usage: $source->connect($sig_name, $dst_obj, $dst_method [, { options }])';
}

sub _destroy {
    my $src_id = shift;
    delete $signal_map{$src_id};
    delete $signal_busy{$src_id};
}

sub connect {
    my $src_obj     = shift;
    my $sig_name    = shift;
    my $dst_obj     = shift;
    my $dst_method;

    _connect_usage() unless blessed($src_obj) &&
                            defined($dst_obj);

    _check_signal_exists(ref($src_obj), $sig_name);

    if (blessed($dst_obj)) {
        $dst_method = shift || _connect_usage();
        croak "Slot '$dst_method' not handled by " . ref($dst_obj)
            unless $dst_obj->can($dst_method);
    }
    else {
        _connect_usage() unless ref($dst_obj) eq 'CODE';
    }

    my $options     = shift || { };
    my $src_id      = refaddr($src_obj);

    # Now badness: we replace the DESTROY that Class::Std dropped into
    # the caller's namespace with our own.
    unless (exists $signal_map{$src_id}) {
        # If there's nothing in the hash for this object we can't have
        # installed our destructor yet - so do it now.

        no strict 'refs';

        my $caller          = ref($src_obj);
        my $destroy_func    = $caller . '::DESTROY';
        my $current_func    = *{ $destroy_func }{ CODE };

        local $^W = 0;  # Disable subroutine redefined warning
        no warnings;    # Need this too.

        *{ $destroy_func } = sub {
            # Destroy our members
            _destroy($src_id);
            # Chain the existing destructor
            $current_func->(@_);
        };
    }

    # Stash the object and method so we can call it later.
    weaken($dst_obj) unless $options->{strong};
    push @{$signal_map{$src_id}->{$sig_name}}, [
        $dst_obj, $dst_method, $options
    ];

    return;
}

sub disconnect {
    my $src_obj = shift;
    my $src_id  = refaddr($src_obj);

    croak 'disconnect must be called as a member'
        unless blessed $src_obj;

    if (@_) {
        my $sig_name = shift;
        _check_signal_exists(ref($src_obj), $sig_name);
        if (@_) {
            my $dst_obj     = shift;
            my $dst_method  = shift;    # optional - undef is ok in the grep below
            my $dst_id      = refaddr($dst_obj);

            my $slots = $signal_map{$src_id}->{$sig_name};
            if (defined $slots) {
                # Nasty block to filter out matching connections.
                @{$slots} = grep {
                    defined $_
                      && defined $_->[0]
                      && ($dst_id != refaddr($_->[0])
                          || (! (defined($dst_method)
                                   && defined($_->[1])
                                   && ($dst_method eq $_->[1]))) )
                } @{$slots};
            }
        }
        else {
            # Delete all connections for given signal
            delete $signal_map{$src_id}->{$sig_name};
        }
    }
    else {
        # Delete /all/ connections for this object
        delete $signal_map{$src_id};
    }
}

sub signals {
    my $caller = caller;

    for my $sig_name (@_) {
        # Name OK?
        _validate_signal_name($sig_name);

        croak "Signal '$sig_name' already declared"
            if UNIVERSAL::can($caller, $sig_name);

        my $sig_func = $caller . '::' . $sig_name;

        # Create the subroutine stub
        no strict 'refs';
        *{ $sig_func } = sub {
            my $self = shift;
            _emit_signal($self, $sig_name, @_);
            # Make sure we don't ever have a return value
            return;
        }
    }

    return;
}

sub import {
    my $caller = caller;

    # Install our exported subs
    no strict 'refs';
    for my $sub ( @exported_subs ) {
        *{ $caller . '::' . $sub } = \&{ $sub };
    }
}

sub DESTROY {
    my $self = shift;

    # Tidy up for us
    my $src_id = refaddr($self);
    _destroy($src_id);

    # and for them.
    $self->SUPER::DESTROY();
}

1; # Magic true value required at end of module
__END__

=head1 NAME

Class::Std::Slots - Provide signals and slots for standard classes.

=head1 VERSION

This document describes Class::Std::Slots version 0.0.1

=head1 SYNOPSIS

    package My::Class::One;
    use Class::Std;
    use Class::Std::Slots;
    {
        signals qw(
            my_signal
        );

        sub my_slot {
            my $self = shift;
            print "my_slot triggered\n";
        }

        sub do_stuff {
            my $self = shift;
            print "Doing stuff...\n";
            $self->my_signal;        # send signal
            print "Done stuff.\n";
        }
    }

    package My::Class::Two;
    use Class::Std;
    use Class::Std::Slots;
    {
        signals qw(
            another_signal
        );

        sub another_slot {
            my $self = shift;
            print "another_slot triggered\n";
            $self->another_signal;
        }
    }

    package main;

    my $ob1 = My::Class::One->new();
    my $ob2 = My::Class::Two->new();

    # No signal yet
    $ob1->do_stuff;

    # Connect to a slot in another class
    $ob1->connect('my_signal', $ob2, 'another_slot');

    # Fires signal
    $ob1->do_stuff;

    # Connect an anon sub as well
    $ob1->connect('my_signal', sub { print "I'm anon...\n"; });

    # Fires signal invoking two slots
    $ob1->do_stuff;

=head1 DESCRIPTION

The slots and signals metaphor allows

=head1 INTERFACE

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

=over

=item C<< Invalid signal name '%s' >>

Signal names have the same syntax as identifier names - you've tried to
use a name that contains a character that isn't legal in an identifier.

=item C<< Signal '%s' undefined >>

Signals are declared by calling the C<signals> subroutine. You're
attempting to connect to an undefined signal.

=item C<< Signal '%s' must be invoked as a method >>

Signals are fired using normal method call syntax. To fire a signal
do something like

    $my_obj->some_signal('Args', 'go', 'here');

=item C<< Attempt to re-enter signal '%s' >>

Signals are not allowed to fire themselves directly or indirectly. This
is an intentional limitation. The ease with which signals can be
connected to slots in complex patterns makes it easy to introduce
unintended loops of mutually triggered signals.

=item C<< Usage: $source->connect($sig_name, $dst_obj, $dst_method [, { options }]) >>

Connect can be called either like this:

    $my_obj->connect('some_signal', $other_obj, 'slot_to_fire');

or like this:

    $my_obj->connect('some_signal', sub { print "Slot fired" });

=item C<< Slot '%s' not handled by %s >>

You're attempting to connect to a slot that isn't implemented by
the target object. Slots are normal member functions.

=item C<< disconnect must be called as a member >>

Disconnect should be called like this:

    # Disconnect one slot
    $my_obj->disconnect('some_signal', $other_obj);

or like this:

    # Disconnect all slots for a signal
    $my_obj->disconnect('some_signal');

or like this:

    # Disconnect all slots for all signals
    $my_obj->disconnect();

=item C<< Signal '%s' aready declared >>

You're attempting to declare a signal that already exists. This may be
because it has been declared as a signal or because the signal name
clashes with a method name.

=back

=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.

Class::Std::Slots requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-class-std-slots@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Andy Armstrong  C<< <andy@hexten.net> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006, Andy Armstrong C<< <andy@hexten.net> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
