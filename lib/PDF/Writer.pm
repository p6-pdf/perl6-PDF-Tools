use v6;

class PDF::Writer {

    use PDF::Grammar:ver(v0.0.8..*);
    use PDF::IO;

    has PDF::IO $!input;
    has $.ast is rw;
    has UInt $.offset;
    has UInt $.prev;
    has UInt $.size;
    has Str $.indent is rw = '';

    submethod TWEAK(:$input) {
        $!input .= coerce( $_ )
            with $input;
    }

    method Str returns Str {
        with $.ast {
            temp $!offset;
            temp $!prev;
            $.write( $_ );
        }
        else {
            nextsame;
        }
    }

    method Blob returns Blob {
	self.Str.encode: "latin-1";
    }

    method write-array( Array $_ ) {
	temp $!indent ~= '  ';  # for indentation of child dictionarys
	('[', .map({ $.write($_) }), ']').join: ' ';
    }

    multi method write-body( Array $_, |c ) {
        temp $!prev = Nil;
        .map({ $.write-body( $_, |c )}).join: "\n";
    }

    multi method write-body( Hash $body, |c ) {
	$!offset //= 0;
	$.write-body( $body, |c );
    }

    #| write the body and return the index
    multi method write-body( Hash $body!, @idx = [], Bool :$write-xref = True --> Str ) {
	my @out = self!make-objects( $body<objects>, @idx );
	@idx.unshift: { :type(0), :offset(0), :gen-num(65535), :obj-num(0) };

	my \trailer-dict = $body<trailer> // {};
	my \trailer-bytes = $write-xref
            ?? self!make-trailer( trailer-dict, @idx )
            !! [~] ( $.write-trailer( trailer-dict ), '%%EOF' );

        @out.push: trailer-bytes;
        $!offset += trailer-bytes.codes  +  2 * "\n".codes;

        @out.join: "\n";
    }

    method !make-objects( @objects, @idx = [] ) {
        @objects.map: -> \obj {
            my \bytes = do with obj<ind-obj> -> $ind-obj {
		my uint $obj-num = $ind-obj[0];
		my uint $gen-num = $ind-obj[1];
		@idx.push: { :type(1), :$!offset, :$gen-num, :$obj-num, :$ind-obj };

                $.write-ind-obj( $ind-obj );
            }
            elsif my \comment = obj<comment> {
                $.write-comment(comment);
            }
            else {
                die "don't know how to serialize body component: {obj.perl}"
            }

            $!offset += bytes.codes + 1;
            bytes;
        }
    }

    method !make-trailer( Hash $trailer, @idx ) {
	@idx = @idx.sort: { $^a<obj-num> <=> $^b<obj-num> || $^a<gen-num> <=> $^b<gen-num> };

	my Hash @xrefs;
        my Hash $xref;

	for @idx {
	    # [ PDF 1.7 ] 3.4.3 Cross-Reference Table:
	    # "Each cross-reference subsection contains entries for a contiguous range of object numbers"
	    my \contiguous = $xref && .<obj-num> && .<obj-num> == $!size;
	    @xrefs.push: ($xref = %( :obj-first-num(.<obj-num>), :entries[] ))
		unless contiguous;
	    $xref<entries>.push: $_;
	    $xref<obj-count>++;
	    $!size = .<obj-num> + 1;
	}

	my Str \xref-str = $.write-xref( @xrefs );
	my UInt \startxref = $.offset;

	my \trailer = [~] (
	    xref-str,
	    $.write-trailer( $trailer, :$!prev, :$!size ),
	    $.write-startxref( startxref ),
	    '%%EOF',
        );

	$!offset += xref-str.codes;
	$!prev = startxref;

        trailer;
    }

    method write-bool( $_ ) {
        .so ?? 'true' !! 'false';
    }

    #| inverter for PDF::Grammar::Content::Actions

    multi method write-content( Array $_ ) {
        .map({ $.write-content($_) }).join("\n");
    }

    multi method write-content( $_ where Pair | Hash) {
        my ($op, $args) = .kv;
        $args //= [];
        $.write-op($op, |@$args);
    }

    multi method write-content( Str $_ ) { $_ }

    #| BI <dict> - BeginImage
    multi method write-op('BI', $arg = :dict{}) {
        my Hash $entries = $arg<dict>;
	join( "\n",
              "BI",
              self!indented($entries.pairs.sort,
                            -> $_ { [~] $.write-name( .key ), ' ', $.write( .value ) }
                           ),
            );
    }
 
   multi method write-op('comment', $_) { $.write-comment($_); }

    #| ID <bytes> - ImageData
    multi method write-op('ID', $image-data) {
        "ID\n" ~ $image-data<encoded>;
    }

    multi method write-op(Str $op, *@args) is default {
        my @vals;
        my Str @comments;
        for @args -> \arg {
            with arg<comment> {
                @comments.push: $_
            }
            else {
                @vals.push: arg;
            }
        }

        my @out = @vals.map: {$.write($_)};
        @out.push: $.write-op( $op );
        @out.push: $.write-comment( @comments.join(' ') )
            if @comments;

        @out.join: ' ';
    }

    multi method write-op( Str $_ ) { .Str }

    multi method write-comment(List $_) {
        .map({ $.write-comment($_) }).join: "\n";
    }

    multi method write-comment(Str $_) {
        m:s{^ '%'} ?? $_ !! '% ' ~ $_
    }

    method write-dict(Hash $dict) {

        # prioritize /Type and /Subtype entries. output /Length as last entry
        my @keys = $dict.keys.sort: {
            when 'Type'          {"0"}
            when 'Subtype' | 'S' | /Type$/ {"1"}
            when 'Length'        {"z"}
            default              {$_}
        };

        join("\n",
             '<<',
             self!indented(@keys,
	                   -> \k { [~] $.write-name(k), ' ', $.write( $dict{k} ) }
	                  ),
             $!indent ~ '>>'
            );

    }

    #| invertors for PDF::Grammar::Function expr term
    #| an array is a sequence of sub-expressions
    multi method write-expr(Array $_) {
	[~] '{ ', .map({ $.write($_) }).join(' '), ' }';
    }

    #| 'if' and 'ifelse' functional expressions
    multi method write-expr(% (:$if!, :$else) ) {
        my @expr = $.write( $if );
        @expr.append: do with $else {
	    ($.write( $_ ), 'ifelse');
        }
        else {
	    ('if')
        }
        @expr.join: ' ';
    }

    method write-hex-char( Str $_ ) {
        die "multi or zero-byte hex character: {.perl}"
           unless .chars == 1;
        die "illegal non-latin hex character: U+" ~ .ord.base(16)
            unless 0 <= .ord <= 0xFF;
        .ord.fmt: '#%02x';
    }

    method write-hex-string( Str $_ ) {
        [~] flat '<', .encode("latin-1").map({ 
            .fmt: '%02x';
        }), '>';
    }

    method write-ind-obj(@_) {
        my (UInt \obj-num, UInt \gen-num, \object where Pair | Hash) = @_;

        "%d %d obj %s\nendobj\n".sprintf(obj-num, gen-num, $.write( object ));
    }

    method write-ind-ref(Array $_) {
        [ .[0], .[1], 'R' ].join: ' ';
    }

    method write-int(Int $_) {.fmt: '%d'}

    constant %Escapes = %(
        "\b" => '\\b', "\f" => '\\f', "\n" => '\\n', "\r" => '\\r',
        "\t" => '\\t', '(' => '\\(', ')' => '\\)', '\\' => '\\\\' );

    method write-literal( Str $_ ) {

        [~] flat '(',
        .encode("latin-1").map({
                my \c = .chr;
                %Escapes{c} // (32 <= $_ <= 126 ?? c !! .fmt('\%03o'));
            }),
           ')';
    }

    constant Name-Reg-Chars = set ('!'..'~').grep({ $_ !~~ /<PDF::Grammar::char-delimiter>/});

    method write-name( Str $_ ) {
        [~] flat '/', .comb.map( {
            when $_ ∈ Name-Reg-Chars { $_ }
            when '#' { '##' }
            default {
                .encode.list.map({.fmt('#%02x')}).join('');
            }
        } )
    }

    method write-null( $ ) { 'null' }

    method write-pdf(% (:$header!, :$body!, :$comment = q<%¥±ë>) ) {
        my Str \header = $.write-header( $header );
        my Str \comment = $.write-comment($comment);
        $!offset = header.codes + comment.codes + 2;  # since format is byte orientated
        # Form Definition Format is normally written without an xref
        my Str \type = $header<type> // 'PDF';
	my Bool $write-xref = type ne 'FDF';
        my \body = $.write-body( $body, :$write-xref );
        (header, comment, body).join: "\n";
    }

    method write-header($_ ) {
        my Str \type = .<type> // 'PDF';
        '%%%s-%.1f'.sprintf(type, .<version> // 1.2);
    }

    multi method write-real( Num $_ ) {
	my \int = .round(1).Int;
	$_ =~= int
	    ?? ~int
	    !! .fmt('%.5f');
    }

    multi method write-real( Numeric $_ ) {
        ~$_
    }

    method write-stream(% (:%dict!, :$encoded = $.input.stream-data( :stream($_) )) ) {
        my $data = $encoded;
        $data = $data.decode("latin-1")
            unless $data.isa(Str);
        %dict<Length> //= :int($data.codes);
        [~] $.write-dict(%dict), " stream\n", $data, "\nendstream";
    }

    method write-trailer(% (:%dict), :$prev) {
        %dict<Prev> = :int($_)
            with $prev;

        %dict<Size> = :int($_)
            with $!size;

        [~] "trailer\n", $.write-dict(%dict), "\n";
    }

    method write-startxref(UInt $_ ) {
        "startxref\n" ~ $.write-int($_) ~ "\n"
    }

    multi method write-xref(Array $_) {
        (flat 'xref',
          .map({ $.write-xref($_) }),
	 '').join: "\n";
    }

    #| write a traditional (PDF 1.4-) cross reference table
    multi method write-xref(% (:$obj-first-num!, :$obj-count!, :$entries!)) {
        (flat
         $obj-first-num ~ ' ' ~ $obj-count,
         $entries.map({
             my Str $status = do given .<type> {
                 when (0) {'f'} # free
                 when (1) {'n'} # inuse
                 when (2) { die "unable to write type-2 (embedded) objects in a PDF 1.4 cross reference table"}
                 default  { die "unhandled index type: $_" }
             };
             die "generation number {.<gen_num>} exceeds 5 digits in PDF 1.4 cross reference table"
                 if .<gen-num> > 99_999;
             die "offset {.<offset>} exceeds 10 digits in PDF 1.4 cross reference table"
                 if .<offset> > 9_999_999_999;
             '%010d %05d %s '.sprintf(.<offset>, .<gen-num>, $status)
         }),
        ).join: "\n";
    }

    proto method write(|c) returns Str {*}

    multi method write( Pair $_!) {
        self."write-{.key}"( .value );
    }

    multi method write( Hash $ast!) {
        $.write( |$ast );
    }

    multi method write( *@args, *%opt ) is default {
        die "unexpected arguments: {[@args].perl}"
            if @args;

        my $key = %opt.keys.sort.first({  $.can("write-$_") })
            or die "unable to handle {%opt.keys} struct: {%opt.perl}";
        my $val = %opt{$key}:delete;
        self."write-$key"($val, |%opt);
    }

    #| handle indentation.
    method !indented(@lines, &sub) {
        temp $!indent ~= '  ';
        @lines ?? @lines.map({ $!indent ~ &sub($_) }).join("\n") !! ();
    }
}
