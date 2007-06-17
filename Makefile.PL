use strict;
use warnings;

use inc::Module::Install;

name          ('File-LinkTree-Builder');
author        ('Ricardo SIGNES <rjbs@cpan.org>');
license       ('perl');
version_from  ('lib/File/LinkTree/Builder.pm');

requires      ('Carp'           => 0);
requires      ('File::Basename' => 0);
requires      ('File::Next' => 0);
requires      ('File::Path' => 0);
requires      ('File::Spec' => 0);

WriteAll();
