package Smolder::Control::Public::Auth;
use strict;
use base 'Smolder::Control';
use Smolder::AuthInfo;
use Smolder::DB::Developer;
use Smolder::DB;
use Smolder::Email;
use HTML::FillInForm;
use Apache::Cookie;

our $HOME_PAGE_URL = "/app/developer";

=head1 NAME 

Smolder::Control::Public::Auth

=head1 DESCRIPTION

Controller module for all auth related activities.

=cut

sub setup {
    my $self = shift;
    $self->start_mode('login');
    $self->run_modes(
        [
            qw(
              login
              process_login
              logout
              show_logout
              forgot_pw
              process_forgot_pw
              timeout
              forbidden
              )
        ]
    );
}

=head1 RUN MODES

=head2 login

Show the login form. Uses the F<Public/Auth/login.tmpl> template.

=cut

sub login {
    my ( $self, $tt_params ) = @_;
    if ($tt_params) {
        return $self->tt_process($tt_params);
    } else {
        return HTML::FillInForm->new()->fill(
            scalarref => $self->tt_process( {} ),
            fobject   => $self->query,
        );
    }
}

=head2 process_login

Process the incoming data from the C<login> mode. If validation passes
the appropriate C<mod_auth_tkt> token is set and the user is either redirected
back to where they were trying to when they were redirected to the C<login> mode,
or taken to the developer home page.

=cut

sub process_login {
    my $self    = shift;
    my $form    = { required => [qw(username password)] };
    my $results = $self->check_rm( 'login', $form )
      || return $self->check_rm_error_page();

    my ( $user, $pw ) = ( $results->valid('username'), $results->valid('password') );

    # see if we have a user with this password
    my ($dev) = Smolder::DB::Developer->search( username => $user );
    if ($dev) {

        # check to see if the password matches the encrypted one
        if ( crypt( $pw, $dev->password ) eq $dev->password ) {

            # figure out which tokens to add
            my @tokens = ('developer');
            push( @tokens, 'admin' ) if ( $dev->admin );

            my $at = Smolder::AuthInfo->new();

            # now add the AuthTKT cookie going out
            my $cookie = $at->cookie(
                uid    => $dev->id,
                tokens => join( ',', @tokens ),
            );
            $self->header_add( -cookie => [$cookie] );

            # url of where to go next
            my $url = $self->query->param('back') || $HOME_PAGE_URL;
            $self->header_type('redirect');
            $self->header_add( -uri => $url );
            Smolder::DB->dbi_commit();
            return "Redirecting to '$url'";
        }
    }

    # if we got here then something failed
    return $self->login( { validation_failed => 1 } );
}

=head2 forgot_pw

Show the Forgot-my-password form. Uses the F<Public/Auth/forgot_pw.tmpl> template.

=cut

sub forgot_pw {
    my ( $self, $tt_params ) = @_;
    $tt_params ||= {};
    return $self->tt_process($tt_params);
}

=head2 process_forgot_pw

Process the incoming data from the C<forgot_pw> mode. If it passes validation
then reset the developer's password to a new random string and then send an
email with the new password (using the F<Email/forgot_pw.tmpl> template) to
that developer. If successful, then return to the C<forgot_pw> mode.

=cut

sub process_forgot_pw {
    my $self = shift;
    my ($developer) = Smolder::DB::Developer->search( username => $self->query->param('username') );
    my $tt_params = {};
    if ($developer) {
        my $new_pw = $developer->reset_password();
        Smolder::DB->dbi_commit();

        # send an email with the new password
        my $error = Smolder::Email->send_mime_mail(
            name      => 'forgot_pw',
            to        => $developer->email,
            subject   => 'Forgot your password',
            tt_params => {
                developer => $developer,
                new_pw    => $new_pw,
            },
        );

        if( $self->log->would_log('debug') ) {
            $self->log->debug(
                "New password for developer " . $developer->username . " is '$new_pw'"
            );
        }
        $tt_params->{success} = 1;
        $tt_params->{email}   = $developer->email;
    } else {
        $tt_params->{not_found} = 1;
    }
    return $self->forgot_pw($tt_params);
}

=head2 logout

Logout the user by unsetting the C<mod_auth_tkt> cookie and then redirecting
them (so that the cookie is sent to the browser) to the C<show_logout> mode.

=cut

sub logout {
    my ( $self, $tt_params ) = @_;
    $tt_params ||= {};

    # remove their auth cookie
    my $at = Smolder::AuthInfo->new();

    # now add the AuthTKT cookie going out
    my $cookie = Apache::Cookie->new(
        $self->param('r'),
        -name    => 'auth_tkt',
        -value   => '',
        -expires => '-1d',
    );
    $self->header_add( -cookie => [$cookie] );
    $self->header_type('redirect');
    $self->header_add( -uri => '/app/public_auth/show_logout' );
    return "Redirecting to '/app/public_auth/show_logout'.";
}

=head2 show_logout

Show the logout screen after a successful logout. Uses the 
F<Public/Auth/show_logout.tmpl> template.

=cut

sub show_logout {
    my ( $self, $tt_params ) = @_;
    $tt_params ||= {};
    return $self->tt_process($tt_params);
}

=head2 timeout

Show the timeout screen if C<mod_auth_tkt> determines
that their ticket is valid but expired.
Uses the F<Public/Auth/timeout.tmpl> template.

=cut

sub timeout {
    my ( $self, $tt_params ) = @_;
    if ($tt_params) {
        return $self->tt_process($tt_params);
    } else {
        return HTML::FillInForm->new()->fill(
            scalarref => $self->tt_process( {} ),
            fobject   => $self->query,
        );
    }
}

=head2 forbidden

Show the forbidden screen if C<mod_auth_tkt> determines
that their ticket is either missing or invalid.
Uses the F<Public/Auth/forbidden.tmpl> template.

=cut

sub forbidden {
    my ( $self, $tt_params ) = @_;
    if ($tt_params) {
        return $self->tt_process($tt_params);
    } else {
        return HTML::FillInForm->new()->fill(
            scalarref => $self->tt_process( {} ),
            fobject   => $self->query,
        );
    }
}

1;
