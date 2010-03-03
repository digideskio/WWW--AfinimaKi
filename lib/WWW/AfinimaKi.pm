package WWW::AfinimaKi;
use strict;

require RPC::XML;
require RPC::XML::Client;
use Digest::MD5	qw(md5_hex);
use Encode;
use Carp;

our $VERSION = '0.2';

use constant KEY_LENGTH => 32;
use constant TIME_DIV   => 12;

=head1 NAME

WWW::AfinimaKi - AfinimaKi Recommendation Engine Client


=head1 SYNOPSIS

    use WWW::AfinimaKi;         # Notice the uppercase "K"!

    my $api = WWW::AfinimaKi->new( $your_api_key, $your_api_secret);

    ...

    $api->set_rate($user_id, $item_id, $rate);

    ...

    my $estimated_rate = $api->estimate_rate($user_id, $rate);

    ...

    my $recommendations = $api->get_recommendations($user_id);
    foreach (@$recommendations) {
        print "item_id: $_->{item_id} estimated_rate: $_->{estimated_rate}\n";
    }

=head1 DESCRIPTION

WWW::AfinimaKi is a simple client for the AfinimaKi Recommendation API. Check http://www.afinimaki.com/api for more details.

=head1 Methods

=head3 new

    my $api = WWW::AfinimaKi->new( 
                    api_key     => $your_api_key, 
                    api_secret  => $your_api_secret, 
                    debug       => $debug_level,
    );

    if (!$api) {
        die "Error construction afinimaki, wrong keys length?";
    }

    new Construct the AfinimaKi object. No nework traffic is generated (the account credentialas are not checked at this point). 

    The given keys must be 32 character long. You can get them at afinimaki.com. Debug level can be 0 or 1.

=cut

sub new {
    my ($class, %args) = @_;  

    my $key     =  $args{api_key};
    my $secret  =  $args{api_secret};
    my $debug   =  $args{debug};
    my $url     =  $args{host};

    # url parameter is undocumented on purpose to simplify.


    if ( length($key) != KEY_LENGTH ) {
        carp "Bad key '$key': it must be " .  KEY_LENGTH . " character long";
        return undef;
    }


    if ( length($secret) != KEY_LENGTH  ) {
        carp "Bad key '$secret': it must be ". KEY_LENGTH . " character long";
        return undef;
    }

    if ( $url && $url !~ /^http:\/\// ) {
        carp "Bad URL given : $url";
        return undef;
    }

    my $self = {
        key     => $key,
        secret  => $secret,
        cli     => RPC::XML::Client->new($url || 'http://api.afinimaki.com/RPC2'),
        debug   => $debug,
    };

    bless $self, $class;
    return $self;
}

sub _auth_code {
    my ($self, $method, $first_arg) = @_;
    return undef if ! $method;

    $first_arg ||= '';

    my $code = 
        $self->{secret} 
        . $method 
        . $first_arg 
        . int( time() / TIME_DIV )
        ;

    return md5_hex( $code );
}

sub send_request {
    my ($self, $method, @args) = @_;

    my $val = $args[0] ? $args[0]->value : undef;


    print STDERR __PACKAGE__ . "$method (".join(', ',  @args) . ") "
        if $self->debug;

    $self->{cli}->send_request(
        $method,
        $self->{key},
        $self->_auth_code($method, $val),
        @args
        );
}


=head2 user-item services

=head3 set_rate

    $api->set_rate($user_id, $item_id, $rate);

    Stores a rate in the server. Waits until the call has ended.

=cut

sub set_rate {
    my ($self, $user_id, $item_id, $rate) = @_;
    return undef if ! $user_id || ! $item_id || ! defined ($rate);

    $self->send_request(
        'set_rate', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
        RPC::XML::i4->new($rate),
        RPC::XML::boolean->new(1),
    );
}


=head3 estimate_rate

    my $estimated_rate = $api->estimate_rate($user_id, $item_id);

    Estimate a rate. Undef is returned if the rate could not be estimated (usually because the given user or the given item does not have many rates).

=cut

sub estimate_rate {
    my ($self, $user_id,  $item_id) = @_;
    return undef if ! $user_id || ! $item_id;

    my $r = $self->send_request(
        'estimate_rate', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
    );

    return 1.0 * $r->value;
}



=head3 estimate_multiple_rates

    my $rates_hashref = $api->estimate_rate($user_id, @item_ids);
        foreach my $item_id (keys %$rates_hashref) {
        print "Estimated rate for $item_id is $rates_hashref->{$item_id}\n";
    }

    Estimate multimple rates. The returned hash has the structure: 
            item_id => estimated_rate

=cut

sub estimate_multiple_rates {
    my ($self, $user_id,  @item_ids) = @_;
    return undef if ! $user_id || ! @item_ids;

    my $r = $self->send_request(
            'estimate_multiple_rates', 
            RPC::XML::i8->new($user_id),
            RPC::XML::array->new( 
                    map {
                        RPC::XML::i8->new($_)
                    } @item_ids
                )
        );
    
    my $ret = {}; 
    my $i = 0;
    foreach (@$r) {
        $ret->{$item_ids[$i++]} = 1.0 * $_->value;
    }

    return $ret;
}


=head3 get_recommendations 

    my $recommendations = $api->get_recommendations($user_id);

    foreach (@$recommendations) {
        print "item_id: $_->{item_id} estimated_rate: $_->{estimated_rate}\n";
    }

    Get a list of user's recommentations, based on users' and community previous rates.
    Recommendations does not include rated or marked items (in the whish or black list).

=cut

sub get_recommendations {
    my ($self, $user_id) = @_;
    return undef if ! $user_id;

    my $r = $self->send_request(
        'get_recommendations', 
        RPC::XML::i8->new($user_id),
        RPC::XML::boolean->new(0),
    );

    return [
        map { {
            item_id         => 1   * $_->[0]->value,
            estimated_rate  => 1.0 * $_->[1]->value,
        } } @$r
    ];
}

=head3 add_to_wishlist

    $api->add_to_wishlist($user_id, $item_id);

    The given $item_id will be added do user's wishlist. This means that id will not
    be in the user's recommentation list anymore. 

=cut

sub add_to_wishlist {
    my ($self, $user_id, $item_id) = @_;
    return undef if ! $user_id || ! $item_id;

    $self->send_request(
        'add_to_wishlist', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
    );
}


=head3 add_to_blacklist

    $api->add_to_blacklist($user_id, $item_id);

    The given $item_id will be added do user's blacklist. This means that id will not
    be in the user's recommentation list anymore. 

=cut

sub add_to_blacklist {
    my ($self, $user_id, $item_id) = @_;
    return undef if ! $user_id || ! $item_id;

    $self->send_request(
        'add_to_blacklist', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
    );
}

=head2 user-user services

=head3 user_user_afinimaki 

    my $afinimaki = $api->user_user_afinimaki($user_id_1, $user_id_2);

    Gets user vs user afinimaki. AfinimaKi range is [0.0-1.0].

=cut

sub user_user_afinimaki {
    my ($self, $user_id_1,  $user_id_2) = @_;
    return undef if ! $user_id_1 || ! $user_id_2;
    
    my $r = $self->send_request(
        'user_user_afinimaki', 
        RPC::XML::i8->new($user_id_1),
        RPC::XML::i8->new($user_id_2),
    );

    return 1.0 * $r->value;
}



=head3 get_soul_mates 

    my $soul_mates = $api->get_soul_mates($user_id);

    foreach (@$soul_mates) {
        print "user_id: $_->{user_id} afinimaki: $_->{afinimaki}\n";
    }

    Get a list of user's soul mates (users with similar tastes). AfinimaKi range is [0.0-1.0].

=cut

sub get_soul_mates {
    my ($self, $user_id) = @_;
    return undef if ! $user_id;

    my $r = $self->send_request(
        'get_soul_mates', 
        RPC::XML::i8->new($user_id),
    );

    return [
        map { {
            user_id         => 1   * $_->[0]->value,
            afinimaki       => 1.0 * $_->[1]->value,
        } } @$r
    ];
}



__END__

=head1 AUTHORS

WWW::AfinimaKi by Matias Alejo Garcia (matiu at cpan.org)

=head1 COPYRIGHT

Copyright (c) 2010 Matias Alejo Garcia. All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=head1 SUPPORT / WARRANTY

The WWW::AfinimaKi is free Open Source software. IT COMES WITHOUT WARRANTY OF ANY KIND.

=head1 BUGS

None discovered yet... please let me know if you run into one.
	

