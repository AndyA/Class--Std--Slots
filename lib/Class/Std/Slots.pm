package Class::Std::Slots;

use warnings;
use strict;
use Carp;
use Scalar::Util qw(blessed refaddr weaken);

use version; our $VERSION = qv('0.0.1');

my %signal_map  = ( );
my %signal_busy = ( );

my @exported_subs = qw(
    connect
    signals
);

sub _validate_signal_name {
    my $sig_name = shift;
    croak "Invalid signal name: $sig_name"
        unless $sig_name =~ /^\w(?:[\w\d])*$/;
}

sub _emit_signal {
    my $self     = shift;
    my $sig_name = shift;
    my $src_id   = refaddr($self);

    if (exists($signal_busy{$src_id}->{$sig_name})) {
        croak "Attempt to re-enter signal $sig_name";
    }

    # Flag this signal as busy
    $signal_busy{$src_id}->{$sig_name}++;

    # Get the slots registered with this signal
    my $slots = $signal_map{$src_id}->{$sig_name};

    # Might have none... It's not an error.
    if (defined $slots) {
        for my $slot (@{$slots}) {
            my ($dst_obj, $dst_method, $options) = @{$slot};
            if (defined($dst_obj)) {

                my @args = @_;
                if ($options->{reveal_source}) {
                    unshift @args, {
                        source  => $self,
                        signal  => $sig_name,
                        options => $options
                    };
                }

                if (blessed($dst_obj)) {
                    $dst_obj->$dst_method(@args);
                }
                else {
                    $dst_obj->(@args);
                }
            }
        }
    }

    delete $signal_busy{$src_id}->{$sig_name};
}

sub _connect_usage {
    croak 'Usage: $source->connect($sig_name, $dst_obj, $dst_method [, { options }])';
}

sub _destroy {
    my $src_id = shift;
}

sub connect {
    my $src_obj     = shift;
    my $sig_name    = shift;
    my $dst_obj     = shift;
    my $dst_method;

    _connect_usage() unless blessed($src_obj) &&
                            defined($dst_obj);

    if (blessed($dst_obj)) {
        $dst_method = shift || _connect_usage();
    }
    else {
        _connect_usage() unless ref($dst_obj) eq 'CODE';
    }

    my $options     = shift || { };

    #croak 'Usage: connect( src_obj, sig_name, dst_obj, dst_method_name, [ options ] )'
    #    unless blessed($src_obj) && defined($dst_method);

    my $src_id = refaddr($src_obj);

    # Now badness: we replace the DESTROY that Class::Std dropped into
    # the caller's namespace with our own.
    unless (exists $signal_map{$src_id}) {
        # If there's nothing in the hash for this object we can't have
        # installed our destructor yet - so do it now.

        no strict 'refs';

        my $caller          = ref($src_obj);
        my $destroy_func    = $caller . '::DESTROY';
        my $current_func    = *{$destroy_func}{CODE};

        local $^W = 0;  # Disable subroutine redefined warning
        no warnings;    # Need this too.

        *{ $destroy_func } = sub {
            _destroy($src_id);
            delete $signal_map{$src_id};
            delete $signal_busy{$src_id};
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

sub signals {
    my $caller = caller;

    for my $sig_name (@_) {
        # Name OK?
        _validate_signal_name($sig_name);

        my $sig_func = $caller . '::' . $sig_name;

        croak "Signal $sig_name is already defined"
            if defined *{ $sig_func };

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
        *{ $caller . '::' . $sub } = \&{$sub};
    }
}

sub DESTROY {
    my $self = shift;

    # Tidy up for us
    my $src_id = refaddr($self);

    delete $signal_map{$src_id};
    delete $signal_busy{$src_id};

    $self->SUPER::DESTROY();
}

1; # Magic true value required at end of module
__END__

=head1 NAME

Class::Std::Slots - [One line description of module's purpose here]


=head1 VERSION

This document describes Class::Std::Slots version 0.0.1


=head1 SYNOPSIS

    use Class::Std::Slots;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.


=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 INTERFACE

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

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
