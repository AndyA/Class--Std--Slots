package Class::Std::Slots;

use warnings;
use strict;
use Carp;
use Scalar::Util qw(blessed refaddr weaken);

use version; our $VERSION = qv('0.0.1');

my %signal_map  = ( );  # maps id -> signame -> array of connected slots
my %signal_busy = ( );  # maps id -> signame -> busy flag
my %patched     = ( );  # classes who's DESTROY we've patched

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
    my $caller      = ref($src_obj);

    # Now badness: we replace the DESTROY that Class::Std dropped into
    # the caller's namespace with our own.
    unless (exists $patched{$caller}) {
        # If there's nothing in the hash for this object we can't have
        # installed our destructor yet - so do it now.

        no strict 'refs';

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

        # Remember we've patched this one...
        $patched{$caller}++;
    }

    # Stash the object and method so we can call it later.
    weaken($dst_obj) unless $options->{strong} || ref($dst_obj) eq 'CODE';
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

Conventionally the ways in which objects of different classes can interact with
each other is designed into those classes; changes to that behaviour require
either changes to the classes in question or the creation of subclasses.

Signals and slots allow objects to be wired together dynamically at run time in
ways that weren't necessarily anticipated by the designers of the classes. For
example consider a class that manages time consuming downloads:

    package My::Downloader;
    use Class::Std;
    {
        sub do_download {
            my $self = shift;
            # ... do something time consuming ...
        }
    }

For a particular application it might be desirable to be able to display a progress
report as the download progresses. Unfortunately C<My::Downloader> isn't wired to
allow that. We could improve C<My::Downloader> by providing a stub function that's
called periodically during a download:

    package My::Downloader::Better;
    use Class::Std;
    {
        sub progress {
            # do nothing
        }

        sub do_download {
            my $self = shift;
            # ... do something time consuming periodically calling progress() ...
        }
    }

Then we could subclass C<My::Downloader::Better> to update a display:

    package My::Downloader::Verbose;
    use base qw(My::Downloader::Better);
    use Class::Std;
    {
        sub progress {
            my $self = shift;
            my $done = shift;
            print "$done % done\n";
        }
    }

That's not bad - but we had to create a subclass - and we'd have to arrange for it
to be created instead of a C<My::Downloader::Better> anytime we want to use it. If
displaying the progress involved updating a progress bar in a GUI we'd need to
embed a reference to the progress bar in each instance of C<My::Downloader::Verbose>.

Instead we could extend C<My::Downloader::Better> to call an arbitrary callback via
a supplied code reference each time C<progress()> was called ... but then we have to
implement the interface that allows the callback to be defined. If we also want
notifications of retries and server failures we'll need still more callbacks. Tedious.

Or we could write C<My::Downloader::Lovely> like this:

    package My::Downloader::Lovely;
    use Class::Std;
    use Class::Std::Slots;
    {
        signals qw(
            progress_update
            server_failure
        );

        sub do_download {
            my $self = shift;
            # ... do something time consuming periodically emitting
            # a progress_update signal like this:
            for (@ages) {
                $self->do_chunk();
                $self->progress_update($done++);
            }
        }
    }

and use it like this:

    use My::Downloader::Lovely;

    my $lovely = My::Downloader::Lovely->new();
    $lovely->do_download();

That behaves just like the original C<My::Downloader> example. Now let's hook up the progress
display - we're using an imaginary GUI toolkit:

    use My::Downloader::Lovely;
    use Pretty::ProgressBar;

    my $lovely = My::Downloader::Lovely->new();
    my $pretty = Pretty::ProgressBar->new();

    # Now the clever bit - hook them together. Whenever the
    # progress_update signal is emitted it'll call
    # $pretty->update_bar($done);
    $lovely->connect('progress_update', $pretty, 'update_bar');

    # Do the download with style
    $lovely->do_download();

We didn't have to subclass or modify C<My::Downloader::Lovely> and we didn't have to clutter its
interface with methods to allow callbacks to be installed. Each signal can be connected to many
slots simultaneously; perhaps we want some debug to show up on the console too:

    use My::Downloader::Lovely;
    use Pretty::ProgressBar;

    my $lovely = My::Downloader::Lovely->new();
    my $pretty = Pretty::ProgressBar->new();

    # Now the clever bit - hook them together. Whenever the
    # progress_update signal is emitted it'll call
    # $pretty->update_bar($done);
    $lovely->connect('progress_update', $pretty, 'update_bar');

    # Add an anon slot to display progress on the console too
    $lovely->connect('progress_update', sub { print 'Done: ', $_[0], "\n"; });

    # Do the download with style
    $lovely->do_download();

Each slot can either be a subroutine reference or an object reference and method name. Anonymous
slots are particularly useful for debugging but they also provide a lightweight way to extend
the behaviour of an existing class.

Only classes that emit signals need use C<Class::Std::Slots> - any method in any class can be
used as a slot.

=head2 Signals?

The signals we refer to here are unrelated to operating system signals. That's why the class is
called C<Class::Std::Slots> instead of Class::Std::Signals.

=head1 INTERFACE

C<Class::Std::Slots> is designed to be used in conjunction with C<Class::Std>. It I<may> work
with classes not based on C<Class::Std> but this is untested. To use it add
C<use Class::Std::Slots> just after C<use Class::Std>

    package My::Class;
    use Class::Std
    use Class::Std::Slots           # <-- add this
    {
        signals qw(                 # <-- add this
            started
            progress
            finished
            retry
        );

        sub my_method {
            my $self = shift;
            # etc
        }
    }

and add a call to C<signals> to declare any signals your class will emit.

C<Class::Std::Slots> will add three public methods to your class: C<signals>, C<connect> and
C<disconnect>.

=over

=item C<signals>

Declare the list of signals that a class can emit. Multiple calls to C<signals> are allowed
but each signal should be declared only once. It is an error to redeclare a signal even in
a subclass or to declare a signal with the same name as a method.

Once declared signals may be called as members of the declaring class and any subclasses.
To emit a signal simply call it:

    $my_obj->started('Starting download');

Any arguments passed to the signal will be passed to any slots registered with it. Signals
never have a return value - any return values from slots are silently discarded.

=item C<connect>

Create a connection between a signal and a slot. Connections are made between objects (i.e.
class instances) rather than between classes. To connect the signal C<started> to a slot
called C<show_status> do something like this:

    $my_thing->connect('started', $uitools, 'show_status');

Whenever C<$my_thing> emits C<started> C<show_status> will be called with any
arguments that were passed to C<started>.

To call a non-member subroutine (which may be an anonymous subroutine or closure) do this:

    $my_thing->connect('debug_out', sub {
        print "@_\n";
    });

Anonymous subroutines are also useful to patch up impedence mismatches between the slot
method and the signal. For example if the signal C<progress> is called with two arguments
(the current progress and the expected total) but the desired slot C<show_progress>
expects to be passed a percentage use something like this:

    $my_thing->connect('progress', sub {
        my ($pos, $all) = @_;
        my $percent = int($pos * 100 / $all);
        $uitools->show_progress($percent);
    });

Normally a slot is passed exactly the arguments that were passed to the signal - so when
C<< $this_obj->some_signal >> has been connected to C<< $that_obj->some_slot >> throwing the
signal like this:

    $this_obj->some_signal(1, 2, 'Here we go');

will cause C<some_slot> to be called like this:

    $that_obj->some_slot(1, 2, 'Here we go');

Sometimes it is useful to be able to write generic slot functions that can be connected
to many different signals and that are capable of interacting with the object that emitted
the signal. The C<reveal_source> option modifies the argument list of the slot function so
that the first argument is a reference to a hash that describes the source of the signal:

    $this_obj->connect('first_signal',  $generic, 'smart_slot', { reveal_source => 1 });
    $this_obj->connect('second_signal', $generic, 'smart_slot', { reveal_source => 1 });
    $that_obj->connect('first_signal',  $generic, 'smart_slot', { reveal_source => 1 });

When C<< $this_obj->first_signal >> is emitted C<< $generic->smart_slot >> will be called with
this hash ref as its first argument:

    {
        source  => $this_obj,
        signal  => 'first_signal',
        options => { reveal_source => 1 }
    }

When C<< $this_obj->second_signal >> is emitted the hash will look like this:

    {
        source  => $this_obj,
        signal  => 'second_signal',
        options => { reveal_source => 1 }
    }

Note that the options hash passed to C<connect> is passed to the slot. This is so that
additional user defined options can be used to influence the behaviour of the slot
function.

The options recognised by C<connect> itself are:

=over

=item reveal_source

Modify slot arg list to include a hash that describes the source of the signal.

=item strong

Normally the reference to the object containing the slot method is weakened (by
calling C<Scalar::Util::weaken> on it). Set this option to make the reference
strong - which means that once an object has been connected to no other
references to it need be kept.

Anonymous subroutine slots are always strongly referred to - so there is no
need to specify the C<strong> option for them.

=back

=item C<disconnect>

Break signal / slot connections. All connections are broken when the signalling
object is destroyed. To break a connection before then use:

    $obj->disconnect('a_signal', $other_obj, 'method');

To break all connections from a signal to slots in a particular object use:

    $obj->disconnect('a_signal', $other_obj);

To break all connections for a particular signal use:

    $obj->disconnect('a_signal');

And finally to break all connections from a signalling object:

    $obj->disconnect();

In other words each additional argument increases the specificity of the connections
that are targetted.

Note that it is not possible to disconnect an anonymous slot subroutine without disconnecting
all other slots connected to the same signal:

    $obj->connect('a_signal', sub { });
    $obj->connect('a_signal', $other_obj, 'a_slot');

    # Can't target the anon slot individually
    $obj->disconnect('a_signal');

If this proves to be an enbearable limitation I'll do something about it.

=back

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

Note that it is illegal to redeclare a signal in a subclass if a parent
already declares the signal. Since signals can't be declared to do
anything other than be a signal it makes no sense to redeclare a
signal in a subclass.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Class::Std::Slots requires no configuration files or environment variables.

=head1 DEPENDENCIES

Class::Std

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

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
