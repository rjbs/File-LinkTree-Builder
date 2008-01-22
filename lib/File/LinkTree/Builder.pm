
use strict;
use warnings;
package File::LinkTree::Builder;

use Carp ();
use Cwd ();
use File::Basename ();
use File::Next;
use File::Path ();
use File::Spec;

=head1 NAME

File::LinkTree::Builder - builds a tree of symlinks based on file metadata

=head1 VERSION

version 0.004

B<ACHTUNG!>: This module is young.  The interface may yet change a little,
probably mostly around the iterator.  Rely on it at your own risk.

=cut

our $VERSION = '0.004';

=head1 SYNOPSIS

This module provides a way to build symlink trees.  Given a path to a set of
files, a way to find file metadata, and a list of symlink paths to produce,
this module will build the symlink trees.

  File::LinkTree::Builder->build_tree({
    storage_root    => 'trove/files',
    link_root       => 'trove/links',
    metadata_getter => \&coderef,
    link_paths      => [
      [ qw(author subject) ],
      [ qw(subject author) ],
    ],
  });

=cut

=head1 METHODS

=head2 build_tree

  File::LinkTree::Builder->build_tree(\%arg);

This method builds a tree of symlinks based on the metadata on the files in the
storage root.  It is exactly equivalent to:

  File::LinkTree::Builder->new(\%arg)->run;

Valid arguments are:

  storage_root    - this is a path in which to start looking for files
                    can be an arrayref; can also be given as storage_roots
  file_filter     - this filters out unwanted files; see File::Next
  metadata_getter - this is a coderef that gets metadata; see below!
  link_root       - this is a path in which the link trees will be built
  link_paths      - this is an arrayref of metadatum names to use; see below!
  hardlink        - if true, the link tree is hard, not symbolic, links
  on_existing     - if 'skip' do not write links that already exist
                    if 'die', go ahead and try, thus dying; default: 'die'

=cut

sub build_tree {
  my ($self, $arg) = @_;
  $self->new($arg)->run;
}

=head2 new

This method returns a new link tree builder, which exists primarily to have is
C<L</run>> method called.  It accepts exactly the same arguments as
C<L</build_tree>>, above.

=cut

sub new {
  my ($class, $arg) = @_;
  $arg ||= {};

  my $on_existing = $arg->{on_existing} || 'die';
  die "invalid 'on_existing' argument"
    unless $on_existing eq 'die' or $on_existing eq 'skip';
  
  die "only give storage_root or storage_roots, not both"
    if $arg->{storage_root} and $arg->{storage_roots};

  $arg->{storage_root} = $arg->{storage_roots} if $arg->{storage_roots};

  my @storage_roots = ref $arg->{storage_root}
                    ? @{$arg->{storage_root}}
                    : $arg->{storage_root};

  my $iterator = File::Next::files(
    {
      file_filter => $arg->{file_filter},
    },
    @storage_roots,
  );

  Carp::croak "no file storage_root" unless $iterator;

  my $self = bless {
    iterator     => $iterator,
    link_paths   => $arg->{link_paths},
    storage_root => \@storage_roots,
    link_root    => $arg->{link_root} || '.',
    hardlink     => ! ! $arg->{hardlink},
    on_existing  => $on_existing,
  } => $class;

  # It's set this way so that in a subclass that has one fixed method to get
  # metadata, it can croak! -- rjbs, 2007-06-12
  $self->set_metadata_getter($arg->{metadata_getter})
    if exists $arg->{metadata_getter};

  return $self;
}

=head2 metadata_for_file

  my $hashref = $builder->metadata_for_file($filename);

Given a filename, this method returns the metadata for a file.  The default
implementation is to call the coderef given to the object constructor.

=cut

sub metadata_for_file {
  my ($self, $filename) = @_;

  return $self->{metadata_getter}->($filename) if $self->{metadata_getter};
  Carp::croak "no metadata getter supplied";
}

=head2 storage_roots

This method returns the path in which to start looking for files that the link
tree will point to.  This can also be called as C<storage_root> for historical
reasons.

=cut

sub storage_root  { @{ $_[0]->{storage_roots} } };
sub storage_roots { @{ $_[0]->{storage_roots} } };

=head2 link_root

This method returns the path in which the link tree is to be built.

=cut

sub link_root { $_[0]->{link_root} }

=head2 iterator

This method returns an iterator which, when called as a coderef, returns the
next file to process.

=cut

sub iterator { $_[0]->{iterator} };

=head2 link_paths

  my @paths = $link_paths;

This method returns a list of arrayrefs, each of which contains metadata names.
These names are used to construct paths under which symlinks will be created to
the files found in the storage root.

=cut

sub link_paths {
  my ($self) = @_;
  return @{ $self->{link_paths} };
}

=head2 hardlink

This method returns true if we've been asked to produce hardlinks.

=cut

sub hardlink { $_[0]->{hardlink} }

=head2 run

This method works through the iterator, building the needed symlinks for each
file.

=cut

# XXX: Refactor me plzkthx! -- rjbs, 2007-06-13
sub run {
  my ($self) = @_;

  FILE: while (my $filename = $self->iterator->()) {
    my $abs_file = File::Spec->rel2abs($filename, Cwd::getcwd);
    my $meta     = $self->metadata_for_file($abs_file);
    my $basename = File::Basename::basename($filename);

    for my $datapath ($self->link_paths) {
      my @path = map {
        defined $meta->{$_} and length $meta->{$_} ? $meta->{$_} : '-'
      } @$datapath;

      for my $path (@path) {
        $path =~ s{/}{-}g;
        $path =~ s{^\.}{_};
      }

      my $path = File::Spec->catfile($self->link_root, @path);
      File::Path::mkpath($path);

      my $link = File::Spec->catfile($path, $basename);

      next FILE if -e $link and $self->_skip_existing_links;

      if ($self->hardlink) {
        link $abs_file => $link
          or die "couldn't create link <$link> to <$abs_file>: $!";
      } else {
        symlink $abs_file => $link
          or die "couldn't create link <$link> to <$abs_file>: $!";
      }
    }
  }
}

sub _skip_existing_links {
  my ($self) = @_;
  return 1 if $self->{on_existing} eq 'skip';
}

=head2 set_metadata_getter

This method is called during initialization to set the object's metadata
getting routine.  It's provided as a method so that subclasses with fixed
metadata-getting routines can croak if one is provided.

=cut

sub set_metadata_getter {
  my ($self, $coderef) = @_;
  $self->{metadata_getter} = $coderef;
}

=head1 TODO

This module needs a bunch of refactoring and probably some better thinking-out
in general.

Specifically, I'd like to make it easier to have relative symlinks.

=head1 AUTHOR

Ricardo SIGNES, C<< <rjbs@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests through the web interface at
L<http://rt.cpan.org>. I will be notified, and then you'll automatically be
notified of progress on your bug as I make changes.

=head1 COPYRIGHT

Copyright 2007 Ricardo SIGNES.  This program is free software;  you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
