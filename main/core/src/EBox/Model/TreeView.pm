# Copyright (C) 2013 Zentyal S.L.
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

package EBox::Model::TreeView;

use base 'EBox::Model::Base';

use EBox;
use EBox::Global;
use EBox::Gettext;
use EBox::Exceptions::Internal;
use EBox::Exceptions::MissingArgument;
use EBox::Exceptions::NotImplemented;
use EBox::Sudo;

use TryCatch::Lite;
use JSON::XS;

sub new
{
    my $class = shift;

    my %opts = @_;
    my $confmodule = delete $opts{'confmodule'};
    $confmodule or
        throw EBox::Exceptions::MissingArgument('confmodule');

    my $self =
    {
        'confmodule' => $confmodule,
        'parent'  => $opts{'parent'},
        'tree' => undef,
    };

    bless ($self, $class);

    return $self;
}

# Method: tree
#
#       Get the tree description. It must NOT be overrided.
#
# Returns:
#
#       hash ref with the tree description
#
sub tree
{
    my ($self) = @_;

    # It's a singleton method
    unless (defined($self->{'tree'}) and
            defined($self->{'tree'}->{'treeDescription'})) {
        $self->_setupTree();
    }

    return $self->{'tree'};
}

sub _setupTree
{
    my ($self) = @_;

    my $tree = $self->_tree();
    $self->{'tree'} = $tree;

    # Set the needed controller and undef setters
#FIXME    $self->_setControllers();

    # Some default values
    unless (defined($self->{'tree'}->{'class'})) {
        $self->{'tree'}->{'class'} = 'treeView';
    }
}

# Method: _tree
#
#    Override this method to describe your tree.
#       This method is (PROTECTED)
#
# Returns:
#
#     tree description. See example on <EBox::Network::Model::GatewayTreeView::_tree>.
#
sub _tree
{
    throw EBox::Exceptions::NotImplemented('_tree');
}

# Method: rootNodes
#
#    Return the top-level nodes of the tree
#
#    This needs to be overrided and implemented on each model
#
# Returns:
#
#    list of hashes ref with the attributes of each root node
#
sub rootNodes
{
    throw EBox::Exceptions::NotImplemented('rootNodes');
}

# Method: childNodes
#
#    Return the child nodes of a given parent node
#
#    This needs to be overrided on each model except in
#    the case of a plain tree with only root nodes, but
#    in that case is probably better to be using a DataTable
#
# Parameters:
#
#    parent - string with the id of the parent node
#
# Returns:
#
#    list of hashes ref with the attributes of each child node
#
sub childNodes
{
    return [];
}

# Method: nodeTypes
#
#    Return the different types a tree can have
#
#    This can be used to set different icons for each
#    type under /data/images/treeview/$type.png
#
# Returns:
#
#    hash ref indexed by type name and hash ref with attributes as value
#
sub nodeTypes
{
    return [];
}

# Method: modelName
#
#    Return the model name which is set by the key 'treeName' when
#    a model tree is described
#
# Returns:
#
#    string containing the model name
#
sub modelName
{
    my ($self) = @_;
    return $self->tree()->{'treeName'};
}

# Method: treeName
#
#        Get the tree name associated to this model
#
# Returns:
#
#        String - containing the tree name
#
sub treeName
{
    my ($self) = @_;

    return $self->tree()->{'treeName'};
}

# Method: printableModelName
#
#       Get the i18ned model name
#
# Returns:
#
#       String - the localisated model name
#
sub printableModelName
{
    my ($self) = @_;

    return $self->tree()->{'printableTreeName'};
}

# Method: menuNamespace
#
#    Fetch the menu namespace which this model belongs to
#
# Returns:
#
#        String - Containing namespace
#
sub menuNamespace
{
    my ($self) = @_;

    if (exists $self->tree()->{'menuNamespace'}) {
        return $self->tree()->{'menuNamespace'};
    } elsif (defined ($self->modelDomain())) {
        # This is autogenerated menuNamespace got from the model
        # domain and the tree name
        my $menuNamespace = $self->modelDomain() . '/Tree/' . $self->modelName();
        return $menuNamespace;
    } else {
        return undef;
    }
}

# Method: help
#
#     Get the help message from the model
#
# Returns:
#
#     String - containing the i18n help message
#
sub help
{
    my ($self) = @_;

    return $self->tree()->{'help'};
}

# Method: modelDomain
#
#     Get the domain where the model is handled. That is, the eBox
#     module which the model belongs to
#
# Returns:
#
#     String - the model domain, the first letter is upper-case
#
sub modelDomain
{
    my ($self) = @_;

    return $self->tree()->{'modelDomain'};
}

sub defaultActions
{
    my ($self) = @_;

    return $self->tree()->{'defaultActions'};
}

sub defaultActionLabels
{
    return {
        'add' => __('Add new'),
        'delete' => __('Delete'),
    };
}

# Method: _HTTPUrlView
#
#   Returns the HTTP URL base used to get the view for this model
#
sub _HTTPUrlView
{
    my ($self) = @_;

    return $self->tree()->{'HTTPUrlView'};
}

# Method: HTTPLink
#
#   The HTTP URL base + directory parameter to get the view for this
#   model
#
# Returns:
#
#   String - the URL to link
#
#   '' - if the _HTTPUrlView is not defined to a non-zero string
#
sub HTTPLink
{
    my ($self) = @_;

    if ( $self->_HTTPUrlView() ) {
        my $link = '/' . $self->_HTTPUrlView();
        my $parentRow = $self->parentRow();
        if ($parentRow) {
            $link .= '?directory=' . $self->directory();
        }
        return $link;
    } else {
        return "";
    }
}

# Method: Viewer
#
#       Method to return the viewer from this model. This method
#       can be overriden
#
# Returns:
#
#       String - the path to the Mason template which acts as the
#       viewer from this kind of model.
#
sub Viewer
{
    return '/ajax/treeView.mas';
}

# Group: Private helper functions

sub _mainController
{
    my ($self) = @_;

    my $tree = $self->{'tree'};

    my $defAction = $tree->{'defaultController'};
    if ( (not defined ( $defAction )) and defined ( $self->modelDomain() )) {
        # If it is not a defaultController, we try to guess it from
        # the model domain and its name
        $defAction = '/' . $self->modelDomain() . '/Controller/' .  $self->{'tree'}->{'treeName'};
    }
    return $defAction;
}

# Method: pageTitle
#
#       Get the i18ned name of the page where the model is contained, if any
#
# Returns:
#
#   string
#
sub pageTitle
{
    my ($self) = @_;

    return $self->tree()->{'pageTitle'};
}

# Method: keywords
#
# Overrides:
#
#   <EBox::Model::Component::keywords>
#
sub keywords
{
    my ($self) = @_;

    my @words = ();

    push(@words, _parse_words($self->pageTitle()));
    push(@words, _parse_words($self->headTitle()));
    push(@words, _parse_words($self->printableName()));
    push(@words, _parse_words($self->printableModelName()));
    push(@words, _parse_words($self->printableRowName()));
    push(@words, _parse_words($self->help()));

    return \@words;
}

# Method: actionHandlerJS
#
#    Return the JavaScript code to be executed when clicking an action button
#    with a node selected.
#
#    Can be overrided in TreeView models but by default shows a modal dialog
#    with a CGI with "ActionType" as name, for example, if the action is
#    'edit' and the type is 'user', from the Users module, the CGI URL
#    will be /Users/EditUser, this can be modified in the actionObjects
#    attribute in nodeTypes()
#
# Parameters:
#
#    action - string with the action to execute
#    type   - string type of the node
#
# Returns:
#
#    hashref with url, title and width of the modal dialog to show
#
sub actionHandlerJS
{
    my ($self, $action, $type) = @_;

    my $actionCGI = ucfirst($action);

    my $actionObject = $self->nodeTypes()->{$type}->{actionObjects}->{$action};
    if ($actionObject) {
        $actionCGI .= $actionObject;
    } else {
        $actionCGI .= ucfirst($type);
    }

    my $url = '/' . $self->modelDomain() . "/$actionCGI";
    my $title = $self->defaultActionLabels()->{$action};
    my $ret = {
        url => $url,
        title => $title,
        width => 640
    };

    return $ret;
}

# Method: clickHandlerJS
#
#    Action to be executed when selecting a node.
#
#    It can be in TreeView models, by default executes the edit action.
#
# Parameters:
#
#    type - string type of the node
#
# Returns:
#
#    hashref in the same format as actionHandlerJS
#
sub clickHandlerJS
{
    my ($self, $type) = @_;

    $self->actionHandlerJS('edit', $type);
}

# Method: jsonData
#
#   Return tree representation in JSON format for jstree
#
# Returns:
#
#   string with the encoded JSON data
#
sub jsonData
{
    my ($self) = @_;

    my @data;

    foreach my $node (@{$self->rootNodes()}) {
        my $type = $node->{type};
        my $metadata = $node->{metadata};
        my $printableName = $node->{printableName};
        my @children = $self->_childData($type, $metadata);
        push (@data, {
            data => $printableName,
            attr => {
                rel => $type,
                id => $node->{id}
            },
            metadata => $metadata,
            children => \@children,
        });
    }

    my $json = encode_json(\@data);
    utf8::decode($json);
    return $json;
}

sub _childData
{
    my ($self, $type, $metadata) = @_;

    my @children;
    foreach my $child (@{$self->childNodes($type, $metadata)}) {
        my $childType = $child->{type};
        my $childMetadata = $child->{metadata};
        my $childPrintableName = $child->{printableName};
        push (@children, {
            data => $childPrintableName,
            metadata => $childMetadata,,
            attr => {
                rel => $childType,
                id => $child->{id}
            },
            children => $self->_childData($childType, $childMetadata),
        });
    }

    return \@children;
}

1;
