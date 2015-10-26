use v6;
use Test;

use PDF::Reader;
use PDF::Writer;
use PDF::DAO;
use PDF::DAO::Doc;
use PDF::Storage::Serializer;
use PDF::Grammar::Test :is-json-equiv;

sub prefix:</>($name){ PDF::DAO.coerce(:$name) };

't/pdf/pdf.in'.IO.copy('t/pdf/pdf-updated.out');

my $doc = PDF::DAO::Doc.open( 't/pdf/pdf-updated.out', :a );
my $reader = $doc.reader;
my $root-obj = $doc<Root>;

{
    my $Pages = $root-obj<Pages>;
    my $Resources = $Pages<Kids>[0]<Resources>;
    my $MediaBox = $Pages<Kids>[0]<MediaBox>;
    my $new-page = PDF::DAO.coerce: { :Type(/'Page'), :$MediaBox, :$Resources, :Parent($Pages) };
    my $contents = PDF::DAO.coerce( :stream{ :decoded("BT /F1 16 Tf  88 250 Td (and they all lived happily ever after!) Tj ET" ) } );
    $new-page<Contents> = $contents;
    $Pages<Kids>.push: $new-page;
    $Pages<Count>++;
}

my $serializer = PDF::Storage::Serializer.new( :$reader );
my $body = $serializer.body( :updates )[0];

is-deeply $body<trailer><dict><Root>, (:ind-ref[1, 0]), 'body trailer dict - Root';
is-deeply $body<trailer><dict><Size>, (:int(11)), 'body trailer dict - Size';
is-deeply $body<trailer><dict><Prev>, (:int(578)), 'body trailer dict - Prev';
my $updated-objects = $body<objects>;
is +$updated-objects, 3, 'number of updates';
is-json-equiv $updated-objects[0], (
    :ind-obj[3, 0, :dict{ Kids => :array[ :ind-ref[4, 0], :ind-ref[9, 0]],
                          Count => :int(2),
                          Type => :name<Pages>,
                         }]), 'altered /Pages';

is-json-equiv $updated-objects[1], (
    :ind-obj[9, 0, :dict{ MediaBox => :array[ :int(0), :int(0), :int(420), :int(595)],
                          Contents => :ind-ref[10, 0],
                          Resources => :dict{ Font => :dict{ F1 => :ind-ref[7, 0]},
                                              ProcSet => :ind-ref[6, 0]},
                          Parent => :ind-ref[3, 0],
                          Type => :name<Page>,
                         }]), 'inserted page';

is-json-equiv $updated-objects[2], (
    :ind-obj[10, 0, :stream{ :encoded("BT /F1 16 Tf  88 250 Td (and they all lived happily ever after!) Tj ET"),
                             :dict{Length => :int(70) },
                            }]), 'inserted content';

my $ind-obj1 = $reader.ind-obj( 3, 0 );
my $ast1 = $ind-obj1.ast;
my $prev1 = $doc.reader.prev;
my $size1 = $doc.reader.size;
$doc.update;
my $prev2 = $doc.reader.prev;
ok $prev2 > $prev1, "reader.prev incremented by update"
   or diag "prev1:$prev1  prev2:$prev2";
my $size2 = $doc.reader.size;
ok $size2 > $size1, "reader.size incremented by update"
   or diag "size1:$size1  size2:$size2";
my $ind-obj2;
lives-ok { $ind-obj2 = $reader.ind-obj( 3, 0 )}, "post update reader access - lives";

ok $ind-obj1 !=== $ind-obj2, 'indirect object has been updated';
my $ast2 = $ind-obj2.ast;
todo "not quite equivalent";
is-deeply $ast1, $ast2, 'indirect object ast equivalence';

is $doc.Size, $size2, 'document trailer - updated Size';
isa-ok $doc<Root><Pages><Kids>[1], PDF::DAO::Dict, 'updated page 2 access';

# now re-read the pdf. Will also test our ability to read a PDF
# with multiple body segments

my $doc2 = PDF::DAO::Doc.open: 't/pdf/pdf-updated.out';
$reader = $doc2.reader;

my $ast = $reader.ast( :rebuild );
is +$ast<pdf><body>, 1, 'single body';
is +$ast<pdf><body>[0]<objects>, 9, 'read-back has object count';
is $ast<pdf><body>[0]<objects>[8], ( :ind-obj[9, 0, :stream{ :dict{ Length => :int(70)},
                                                          :encoded("BT /F1 16 Tf  88 250 Td (and they all lived happily ever after!) Tj ET")},
                              ]), 'inserted content';

# do a full rewrite of the updated PDF. Output should be cleaned up, with a single body and
# cleansed of old object versions.
ok $doc2.save-as('t/pdf/pdf-updated-and-rewritten.out', :rebuild), 'save-as :rebuild';

done-testing;
