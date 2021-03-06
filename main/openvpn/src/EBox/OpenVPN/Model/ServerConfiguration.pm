# Copyright (C) 2008-2013 Zentyal S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
use strict;
use warnings;

package EBox::OpenVPN::Model::ServerConfiguration;

use base 'EBox::Model::DataForm';

use EBox::Global;
use EBox::Gettext;
use EBox::Validate qw(:all);
use EBox::Exceptions::External;
use EBox::Exceptions::DataExists;

use EBox::Types::Boolean;
use EBox::Types::HasMany;
use EBox::Types::Select;
use EBox::Types::Password;
use EBox::Types::DomainName;
use EBox::Types::Host;
use EBox::Types::IPNetwork;
use EBox::Types::IPAddr;

use EBox::OpenVPN::Server;
use EBox::OpenVPN::Types::PortAndProtocol;
use EBox::OpenVPN::Types::Certificate;
use EBox::OpenVPN::Types::TlsRemote;

use EBox::View::Customizer;

use constant ALL_INTERFACES => '_ALL';

sub new
{
    my $class = shift;
    my %parms = @_;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    return $self;
}

sub _table
{
    my @tableHead =
        (
         new EBox::OpenVPN::Types::PortAndProtocol(

             fieldName => 'portAndProtocol',
             printableName => __('Server port'),
             editable => 1,
             ),
         new EBox::Types::IPNetwork(
             fieldName => 'vpn',
             printableName => __('VPN address'),
             editable => 1,
             help => __('Use a network address which is not used by this ' .
                        'machine')
             ),

         new EBox::OpenVPN::Types::Certificate(
             fieldName => 'certificate',
             printableName => __('Server certificate'),

             editable       => 1,
             ),

         new EBox::OpenVPN::Types::TlsRemote(
                 fieldName => 'tlsRemote',
                 printableName => __('Client authorization by common name'),
                 editable => 1,
                 help => __('If disabled, any client with a certificate ' .
                            'generated by Zentyal will be able to connect. ' .
                            'If enabled, only certificates whose common ' .
                            'name begins with the selected value will be ' .
                            'able to connect.'
                           )
                 ),
         new EBox::Types::Boolean(
                 fieldName =>  'tunInterface',
                 printableName => __('TUN interface'),
                 editable => 1,
                 defaultValue => 0,
                 ),
         new EBox::Types::Boolean(
                 fieldName =>  'masquerade',
                 printableName => __('Network Address Translation'),
                 editable => 1,
                 defaultValue => 0,
                 help => __('Enable it if this VPN server is not the default gateway')
                 ),
         new EBox::Types::Boolean(
                 fieldName => 'clientToClient',
                 printableName => __('Allow client-to-client connections'),
                 editable => 1,
                 defaultValue => 0,
                 help => __('Enable it to allow client machines of this VPN ' .
                            'to see each other')
                 ),
         new EBox::Types::Boolean(
                 fieldName => 'pullRoutes',
                 printableName => __('Allow Zentyal-to-Zentyal tunnels'),
                 editable => 1,
                 defaultValue => 0,
                 help => __('Enable it if this VPN is used to connect to ' .
                            'another Zentyal')
                 ),
         new EBox::Types::Password(
                 fieldName => 'ripPasswd',
                 printableName => __('Zentyal-to-Zentyal tunnel password'),
                 minLength => 6,
                 editable => 1,
                 optional => 1,

                 ),
         new EBox::Types::Boolean(
                 fieldName => 'rejectRoutes',
                 printableName => __('Reject routes pushed by Zentyal tunnel clients'),
                 editable => 1,
                 defaultValue => 0,
                 help => __('When checked this server will not take any route ' .
                            'advertised by its client')
                 ),
         new EBox::Types::Select(
                 fieldName  => 'local',
                 printableName => __('Interface to listen on'),
                 editable => 1,
                 populate      => \&_populateLocal,
                 defaultValue => ALL_INTERFACES,
                 ),
         new EBox::Types::Boolean(
             fieldName => 'redirectGw',
             printableName => __('Redirect gateway'),
             editable => 1,
             defaultValue => 0,
             help => __('Makes Zentyal the default gateway for the client'),
            ),
         new EBox::Types::Host(
             fieldName => 'dns1',
             printableName => __('First nameserver'),
             editable => 1,
             optional => 1,

            ),
         new EBox::Types::Host(
             fieldName => 'dns2',
             printableName => __('Second nameserver'),
             editable => 1,
             optional => 1,
            ),
         new EBox::Types::DomainName(
             fieldName => 'searchDomain',
             printableName => __('Search domain'),
             editable => 1,
             optional => 1,
            ),
         new EBox::Types::Host(
             fieldName => 'wins',
             printableName => __('WINS server'),
             editable => 1,
             optional => 1,
            ),

         );

    my $dataTable =
    {
        'tableName'               => __PACKAGE__->nameFromClass(),
        'printableTableName' => __('Server configuration'),
        'automaticRemove' => 1,
        'defaultController' => '/OpenVPN/Controller/ServerConfiguration',
        'defaultActions' => ['add', 'del', 'editField',  'changeView' ],
        'tableDescription' => \@tableHead,
        'class' => 'dataTable',
        'printableRowName' => __('server'),
        'sortedBy' => 'name',
        'modelDomain' => 'OpenVPN',
    };

    return $dataTable;
}

# Method: viewCustomizer
#
#   Overrides <EBox::Model::DataTable::viewCustomizer> to implement
#   a custom behaviour to show and hide source and destination ports
#   depending on the protocol
#
#
sub viewCustomizer
{
    my ($self) = @_;
    my $customizer = new EBox::View::Customizer();
    $customizer->setModel($self);
    my $tunnelParams = [qw/ripPasswd rejectRoutes/];
    my $noTunnelParams = [qw/clientToClient redirectGw dns1 dns2 searchDomain wins/];

    $customizer->setOnChangeActions(
            { pullRoutes =>
                {
                on  => { enable  => $tunnelParams,
                         disable => $noTunnelParams,
                        },
                off => {
                        enable  => $noTunnelParams,
                        disable => $tunnelParams
                       },
                }
            });
    return $customizer;
}

sub name
{
    __PACKAGE__->nameFromClass(),
}

sub _populateLocal
{
    my @options;

    my $network = EBox::Global->modInstance('network');

    my @enabledIfaces = grep {
        $network->ifaceMethod($_) ne 'notset'
    } @{ $network->ifaces() };

    @options = map { { value => $_ } }  @enabledIfaces;

    push @options,  {
                     value => ALL_INTERFACES,
                      printableValue => __('All network interfaces'),
                    };

    return \@options;
}

sub validateTypedRow
{
    my ($self, $action, $params_r, $actual_r) = @_;

    $self->_uniqPortAndProtocol($action, $params_r, $actual_r);

    $self->_checkVPN($action, $params_r, $actual_r);

    $self->_checkServerCertificate($action, $params_r, $actual_r);

    $self->_checkRipPasswd($action, $params_r, $actual_r);

#    $self->_checkMasqueradeIsAvailable($action, $params_r, $actual_r);

    $self->_checkIface($action, $params_r, $actual_r);
#    $self->_checkIfaceAndMasquerade($action, $params_r, $actual_r);

    $self->_checkTlsRemote($action, $params_r, $actual_r);

    $self->_checkTunnelForbiddenParams($action, $params_r, $actual_r);

    $self->_checkPortIsAvailable($action, $params_r, $actual_r);
}

sub _checkRipPasswd
{
    my ($self, $action, $params_r, $actual_r) = @_;

    return unless (
                   (exists $params_r->{ripPasswd}) or
                   (exists $params_r->{pullRoutes})
                  );

    my $pullRoutes = exists $params_r->{pullRoutes} ?
                                    $params_r->{pullRoutes}->value() :
                                    $actual_r->{pullRoutes}->value();
    my $ripPasswd  = exists $params_r->{ripPasswd} ?
                                    $params_r->{ripPasswd}->value() :
                                    $actual_r->{ripPasswd}->value();

    return if (not $pullRoutes); # only ripPasswd is needed when pullRoutes
                                 #  is on

    $ripPasswd or
        throw EBox::Exceptions::External(
          __('Zentyal to Zentyal tunnel option requires a RIP password')
                                        );
}

sub _checkVPN
{
    my ($self, $action, $params_r, $actual_r) = @_;

    return unless ( exists $params_r->{vpn} );

    my $vpnAddress = $params_r->{vpn}->printableValue();
    # check other servers VPN networks
    $self->_uniqVPNAddress($vpnAddress);

    # check interfaces networks
    my $network = EBox::Global->getInstance()->modInstance('network');
    foreach my $iface (@{ $network->ifaces( )}) {
        my @addresses = @{  $network->ifaceAddresses($iface) };
        foreach my $addr_r (@addresses) {
            my $address = $addr_r->{address};
            my $netmask = $addr_r->{netmask};
            my $ipnetwork = EBox::NetWrappers::ip_network($address, $netmask);
            my $ipnetworkWithMask = EBox::NetWrappers::to_network_with_mask($ipnetwork, $netmask);

            if ($ipnetworkWithMask eq $vpnAddress) {
                throw EBox::Exceptions::External(
                    __x('The VPN address {addr} is already used by interface {iface}',
                        addr => $vpnAddress,
                        iface => $iface,));
            }
        }
    }
}

sub _uniqVPNAddress
{
    my ($self, $vpnAddress) = @_;
    my $olddir = $self->directory();

    my $parentId = $self->parentRow()->id();
    my $serverList = $self->parentModule()->model('Servers');
    foreach my $id ( @{ $serverList->ids()}) {
        if ($parentId eq $id) {
            next;
        }
        my $row = $serverList->row($id);
        my $serverConf = $row->subModel('configuration');
        my $other      = $serverConf->row()->elementByName('vpn');

        if ($vpnAddress eq $other->printableValue()) {
            throw EBox::Exceptions::External(
                    __('Other server is using the same VPN address, please choose another')
                    );
        }
    }

    $self->setDirectory($olddir);
}

sub _uniqPortAndProtocol
{
    my ($self, $action, $params_r) = @_;

    exists $params_r->{portAndProtocol}
        or return;
    my $olddir = $self->directory();

    my $portAndProtocol = $params_r->{portAndProtocol};

    my $parentId = $self->parentRow()->id();
    my $serverList = $self->parentModule()->model('Servers');
    foreach my $id ( @{ $serverList->ids()}) {
        if ($parentId eq $id) {
            next;
        }
        my $row = $serverList->row($id);
        my $serverConf = $row->subModel('configuration');
        my $other      = $serverConf->portAndProtocolType();

        if ($portAndProtocol->cmp($other) == 0) {
            throw EBox::Exceptions::External(
                    __('Other server is listening on the same port')
                    );
        }
    }

    $self->setDirectory($olddir);
}

sub _checkPortIsAvailable
{
    my ($self, $action, $params_r, $actual_r) = @_;
    my @ifacesToCheck;

    my $portAndProtocolNotChanged =  (not exists $params_r->{portAndProtocol} );
    my $localIfaceNotChanged      =    (not exists $params_r->{local} );
    if ( $portAndProtocolNotChanged and $localIfaceNotChanged ) {
        return;
    }

    my $local = exists $params_r->{local} ?
                    $params_r->{local}->value() :
                    $actual_r->{local}->value();
    if ($local eq ALL_INTERFACES) {
        $local = undef;
    }

    my $portAndProtocol = exists $params_r->{portAndProtocol} ?
                                   $params_r->{portAndProtocol} :
                                   $actual_r->{'portAndProtocol'};
    my $proto = $portAndProtocol->protocol();
    my $port  = $portAndProtocol->port();

    my $ownModuleName = $self->parentModule()->name();
    my @modules = grep {
                       ($_->can('usesPort')) and
                      ($_->name() ne $ownModuleName)
                  }  @{EBox::Global->getInstance()->modInstances()};
    foreach my $mod (@modules) {
        if ($mod->usesPort($proto, $port, $local)) {
            throw EBox::Exceptions::External(
                __x(
                    'Port {p}/{pr} is in use by {mod}',
                    p => $portAndProtocol->printableValue(),
                    pr => $proto,
                    mod => $mod->name()
                       )
               );
        }
    }
}

sub _alreadyCheckedAvailablity
{
    my ($self, $proto, $port, $local, $actual_r) = @_;

    # avoid falses positives
    my ($oldProto, $oldPort, $oldLocal) = (
            $actual_r->{portAndProtocol}->protocol(),
            $actual_r->{portAndProtocol}->port(),
            $actual_r->{local}->value(),
            );
    my $samePort  = $port eq $oldPort;
    my $sameProto = $proto eq $oldProto;
    my $sameLocal = $local eq $oldLocal;

    if ($local eq ALL_INTERFACES) {
        if ($sameProto and $samePort) {
            # we have already checked
            return 1;
        }
    }
    else {
        if ($sameProto and $samePort and $sameLocal) {
            # we have already checked,
            return 1;
        }
    }

    return 0;
}

#XXX this must be in a iface type...
sub _checkIface
{
    my ($self, $action, $params_r, $actual_r) = @_;

    $params_r->{'local'} or
        return;

    my $iface   = $params_r->{'local'}->value();
    if ($iface eq ALL_INTERFACES) {
        return;
    }

    my $network = EBox::Global->modInstance('network');

    if (not $network->ifaceExists($iface) ) {
        throw EBox::Exceptions::External(
            __x('The interface {iface} does not exist'), iface => $iface);
    }

    if ( $network->ifaceMethod($iface) eq 'notset') {
        throw EBox::Exceptions::External(
            __x('The interface {iface} is not configured'), iface => $iface);
    }
}

sub _checkMasqueradeIsAvailable
{
    my ($self, $action, $params_r, $actual_r) = @_;

    my $masquerade = exists $params_r->{masquerade} ?
                                 $params_r->{masquerade}->value() :
                                 $actual_r->{masquerade}->value();
    if (not $masquerade ) {
        return;
    }

    my $firewall = EBox::Global->modInstance('firewall');
    if (not $firewall) {
        throw EBox::Exceptions::External(
          __('Cannot use Network Address translation because it requires the ' .
             'firewall module. The module is neither installed or activated')
                                        );
    }

    if (not $firewall->isEnabled()) {
        throw EBox::Exceptions::External(
          __('Cannot use Network Address translation because it requires the ' .
              'firewall module enabled. Please activate it and try again')
                                        );
    }
}

sub _checkIfaceAndMasquerade
{
    my ($self, $action, $params_r, $actual_r) = @_;
    my $masquerade = exists $params_r->{masquerade} ?
                                 $params_r->{masquerade}->value() :
                                 $actual_r->{masquerade}->value();

    if ($masquerade) {
        # with masquerade either internal or external interfaces are correct
        return;
    }

    my $local   = exists $params_r->{local} ?
                                 $params_r->{local}->value() :
                                 $actual_r->{local}->value();

    my $network = EBox::Global->modInstance('network');

    if ($local eq ALL_INTERFACES) {
        # check that at least there is one external interface
        my $externalIfaces = @{ $network->ExternalIfaces() };
        if (not $externalIfaces) {
            throw EBox::Exceptions::External(
             __('At least one external interface is needed to connect to the ' .
                'server unless network address translation option is enabled')
                                            );
        }
    }
    else {
        my $external = $network->ifaceIsExternal($local);
        if (not $external) {
            throw EBox::Exceptions::External(
              __('The interface must be a external interface, unless ' .
              'Network Address Translation option is on')
                                            )
        }
    }

}

sub _checkServerCertificate
{
    my ($self, $action, $params_r, $actual_r) = @_;

    (exists $params_r->{certificate}) or
        return;

    my $cn = $params_r->{certificate}->value();
    EBox::OpenVPN::Server->checkCertificate($cn);
}

sub _checkTlsRemote
{
    my ($self, $action, $params_r, $actual_r) = @_;

    (exists $params_r->{tlsRemote}) or
        return;

    my $cn = $params_r->{tlsRemote}->value();

    if ($cn == 0) {
        # TLS rmeote option disabled, nothing to check
        return;
    }

    EBox::OpenVPN::Server->checkCertificate($cn);
}

sub _checkTunnelForbiddenParams
{
    my ($self, $action, $params_r, $all_r) = @_;
    if (not $all_r->{pullRoutes}->value()) {
        # no tunnel, no checks needed
        return;
    }

    my @forbidParams = qw(dns1 dns2 searchDomain wins);
    foreach my $param (@forbidParams) {
        if ($all_r->{$param}->value()) {
            throw EBox::Exceptions::External(
                __x('{par} is not compatible with Zentyal-to-Zentyal tunnel',
                    par => $all_r->{$param}->printableName()
                   )
               )
        }
    }
}

# The interface type resides in the ServerModels so we must set it in the
# parentRow
sub updatedRowNotify
{
    my ($self, $row, $oldRow, $force) = @_;

    my $toSet = $row->valueByName('tunInterface') ? 'tun' : 'tap';
    my $parentRow = $self->parentRow();
    my $ifaceType = $parentRow->elementByName('interfaceType');
    if ($ifaceType->value() ne $toSet) {
        $ifaceType->setValue($toSet);
        $parentRow->store();
    }
}

sub configured
{
    my ($self) = @_;

    $self->portAndProtocolType()->port()     or return 0;
    $self->portAndProtocolType()->protocol() or return 0;

    $self->vpnType()->printableValue ne ''    or return 0;

    my $cn = $self->certificate();
    $cn
        or return 0;
    EBox::OpenVPN::Server->checkCertificate($cn);

    return 1;
}

# Method: pageTitle
#
#   Overrides <EBox::Model::DataTable::pageTitle>
#   to show the name of the domain
sub pageTitle
{
    my ($self) = @_;

    my $parentRow = $self->parentRow();
    if (not $parentRow) {
        # workaround: sometimes with a logout + apache restart the directory
        # parameter is lost. (the apache restart removes the last directory used
        # from the models)
        EBox::Exceptions::ComponentNotExists->throw('Directory parameter and attribute lost');
    }

    return $parentRow->printableValueByName('name');
}

1;

