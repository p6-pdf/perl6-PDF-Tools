use v6;

use PDF::Storage::Input;

class PDF::Storage::Input::IOH
    is PDF::Storage::Input {

    has IO::Handle $.value is rw;
    has Str $!str;
    has UInt $.codes is rw;

    BEGIN constant SEEK-FROM-START = 0;
    BEGIN constant SEEK-FROM-EOF = 2;

    multi submethod BUILD( IO::Handle :$!value! ) {
        $!value.seek( 0, SEEK-FROM-EOF );
        $!codes = $!value.tell;
        $!value.seek( 0, SEEK-FROM-START );
    }

    multi method Str( ) {
        $.value.seek( 0, SEEK-FROM-START );
        $!str //= $.value.slurp-rest;
    }

    multi method substr( WhateverCode $from-whatever!, |c ) {
        my UInt $from = $from-whatever( $.codes );
        $.substr( $from, |c );
    }

    multi method substr( UInt $from!, UInt $length = $.codes - $from + 1) {
        return $!str.substr( $from, $length )
            if $!str.defined;
        $!value.seek( $from, SEEK-FROM-START );
        my $buf = $.value.read( $length );
        $buf.decode('latin-1');
    }
}
