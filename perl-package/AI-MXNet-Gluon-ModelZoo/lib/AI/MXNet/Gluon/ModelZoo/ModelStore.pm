# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

package AI::MXNet::Gluon::ModelZoo::ModelStore;
use strict;
use warnings;
use AI::MXNet::Function::Parameters;

=head1 NAME

    AI::MXNet::Gluon::ModelZoo::ModelStore - Model zoo for pre-trained models.
=cut

use AI::MXNet::Gluon::Utils qw(download check_sha1);
use IO::Uncompress::Unzip qw(unzip);
use File::Path qw(make_path);

my %_model_sha1 = map { $_->[1] => $_->[0] } (
    ['44335d1f0046b328243b32a26a4fbd62d9057b45', 'alexnet'],
    ['f27dbf2dbd5ce9a80b102d89c7483342cd33cb31', 'densenet121'],
    ['b6c8a95717e3e761bd88d145f4d0a214aaa515dc', 'densenet161'],
    ['2603f878403c6aa5a71a124c4a3307143d6820e9', 'densenet169'],
    ['1cdbc116bc3a1b65832b18cf53e1cb8e7da017eb', 'densenet201'],
    ['ed47ec45a937b656fcc94dabde85495bbef5ba1f', 'inceptionv3'],
    ['9f83e440996887baf91a6aff1cccc1c903a64274', 'mobilenet0.25'],
    ['8e9d539cc66aa5efa71c4b6af983b936ab8701c3', 'mobilenet0.5'],
    ['529b2c7f4934e6cb851155b22c96c9ab0a7c4dc2', 'mobilenet0.75'],
    ['6b8c5106c730e8750bcd82ceb75220a3351157cd', 'mobilenet1.0'],
    ['36da4ff1867abccd32b29592d79fc753bca5a215', 'mobilenetv2_1.0'],
    ['e2be7b72a79fe4a750d1dd415afedf01c3ea818d', 'mobilenetv2_0.75'],
    ['aabd26cd335379fcb72ae6c8fac45a70eab11785', 'mobilenetv2_0.5'],
    ['ae8f9392789b04822cbb1d98c27283fc5f8aa0a7', 'mobilenetv2_0.25'],
    ['a0666292f0a30ff61f857b0b66efc0228eb6a54b', 'resnet18_v1'],
    ['48216ba99a8b1005d75c0f3a0c422301a0473233', 'resnet34_v1'],
    ['0aee57f96768c0a2d5b23a6ec91eb08dfb0a45ce', 'resnet50_v1'],
    ['d988c13d6159779e907140a638c56f229634cb02', 'resnet101_v1'],
    ['671c637a14387ab9e2654eafd0d493d86b1c8579', 'resnet152_v1'],
    ['a81db45fd7b7a2d12ab97cd88ef0a5ac48b8f657', 'resnet18_v2'],
    ['9d6b80bbc35169de6b6edecffdd6047c56fdd322', 'resnet34_v2'],
    ['ecdde35339c1aadbec4f547857078e734a76fb49', 'resnet50_v2'],
    ['18e93e4f48947e002547f50eabbcc9c83e516aa6', 'resnet101_v2'],
    ['f2695542de38cf7e71ed58f02893d82bb409415e', 'resnet152_v2'],
    ['264ba4970a0cc87a4f15c96e25246a1307caf523', 'squeezenet1.0'],
    ['33ba0f93753c83d86e1eb397f38a667eaf2e9376', 'squeezenet1.1'],
    ['dd221b160977f36a53f464cb54648d227c707a05', 'vgg11'],
    ['ee79a8098a91fbe05b7a973fed2017a6117723a8', 'vgg11_bn'],
    ['6bc5de58a05a5e2e7f493e2d75a580d83efde38c', 'vgg13'],
    ['7d97a06c3c7a1aecc88b6e7385c2b373a249e95e', 'vgg13_bn'],
    ['649467530119c0f78c4859999e264e7bf14471a9', 'vgg16'],
    ['6b9dbe6194e5bfed30fd7a7c9a71f7e5a276cb14', 'vgg16_bn'],
    ['f713436691eee9a20d70a145ce0d53ed24bf7399', 'vgg19'],
    ['9730961c9cea43fd7eeefb00d792e386c45847d6', 'vgg19_bn']
);

my $apache_repo_url = 'http://apache-mxnet.s3-accelerate.dualstack.amazonaws.com/';
my $_url_format = '%sgluon/models/%s.zip';

func short_hash($name)
{
    Carp::confess("model $name is not available in model zoo") unless exists $_model_sha1{$name};
    return substr($_model_sha1{$name}, 0, 8);
}

=head2 get_model_file

    Return location for the pretrained on local file system.

    This function will download from online model zoo when model cannot be found or has mismatch.
    The root directory will be created if it doesn't exist.

    Parameters
    ----------
    $name : Str
        Name of the model.
    :$root : Str, default '~/.mxnet/models'
        Location for keeping the model parameters.

    Returns
    -------
    $file_path
        Path to the requested pretrained model file.
=cut

method get_model_file(Str $name, Str :$root='~/.mxnet/models')
{
    my $file_name = "$name-".short_hash($name);
    $root =~ s/~/$ENV{HOME}/;
    my $file_path = "$root/$file_name.params";
    my $sha1_hash = $_model_sha1{$name};
    if(-f $file_path)
    {
        if(check_sha1($file_path, $sha1_hash))
        {
            return $file_path;
        }
        else
        {
            warn("Mismatch in the content of model file detected. Downloading again.\n");
        }
    }
    else
    {
        warn("Model file is not found. Downloading.\n");
    }

    if(not -d $root)
    {
        make_path($root);
    }

    my $zip_file_path = "$root/$file_name.zip";
    my $repo_url = $ENV{MXNET_GLUON_REPO}//$apache_repo_url;
    if($repo_url !~ /\/$/)
    {
        $repo_url .= '/';
    }
    download(
        sprintf($_url_format, $repo_url, $file_name),
        path=>$zip_file_path,
        overwrite=>1
    );
    unzip($zip_file_path, $file_path);
    unlink $zip_file_path;
    if(check_sha1($file_path, $sha1_hash))
    {
        return $file_path;
    }
    else
    {
        Carp::confess("Downloaded file $file_path has different hash. Please try again.");
    }
}

=head2 purge

    Purge all pretrained model files in local file store.

    Parameters
    ----------
    root : str, default '~/.mxnet/models'
        Location for keeping the model parameters.
=cut

method purge(Str $root='~/.mxnet/models')
{
    $root =~ s/~/$ENV{HOME}/;
    map { unlink } glob("$root/*.params");
}

1;
