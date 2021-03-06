#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

OS_ROOT=$(dirname "${BASH_SOURCE}")/../..
source "${OS_ROOT}/hack/util.sh"
source "${OS_ROOT}/hack/cmd_util.sh"
os::log::install_errexit

# This test validates user level policy

os::cmd::expect_failure_and_text 'oc policy add-role-to-user' 'you must specify a role'
os::cmd::expect_failure_and_text 'oc policy add-role-to-user -z NamespaceWithoutRole' 'you must specify a role'
os::cmd::expect_failure_and_text 'oc policy add-role-to-user view' 'you must specify at least one user or service account'

os::cmd::expect_success 'oc policy add-role-to-group cluster-admin system:unauthenticated'
os::cmd::expect_success 'oc policy add-role-to-user cluster-admin system:no-user'
os::cmd::expect_success 'oc get rolebinding/cluster-admin --no-headers'
os::cmd::expect_success_and_text 'oc get rolebinding/cluster-admin --no-headers' 'system:no-user'

os::cmd::expect_success 'oc policy add-role-to-user cluster-admin -z=one,two --serviceaccount=three,four'
os::cmd::expect_success 'oc get rolebinding/cluster-admin --no-headers'
os::cmd::expect_success_and_text 'oc get rolebinding/cluster-admin --no-headers' 'one'
os::cmd::expect_success_and_text 'oc get rolebinding/cluster-admin --no-headers' 'four'

os::cmd::expect_success 'oc policy remove-role-from-group cluster-admin system:unauthenticated'

os::cmd::expect_success 'oc policy remove-role-from-user cluster-admin system:no-user'
os::cmd::expect_success 'oc policy remove-role-from-user cluster-admin -z=one,two --serviceaccount=three,four'
os::cmd::expect_success 'oc get rolebinding/cluster-admin --no-headers'
os::cmd::expect_success_and_not_text 'oc get rolebinding/cluster-admin --no-headers' 'four'

os::cmd::expect_success 'oc policy remove-group system:unauthenticated'
os::cmd::expect_success 'oc policy remove-user system:no-user'

# adjust the cluster-admin role to check defaulting and coverage checks
# this is done here instead of an integration test because we need to make sure the actual yaml serializations work
workingdir=$(mktemp -d)
cp ${OS_ROOT}/test/fixtures/bootstrappolicy/cluster_admin_1.0.yaml ${workingdir}
os::util::sed "s/RESOURCE_VERSION//g" ${workingdir}/cluster_admin_1.0.yaml
os::cmd::expect_success "oc create -f ${workingdir}/cluster_admin_1.0.yaml"
os::cmd::expect_success 'oadm policy add-cluster-role-to-user alternate-cluster-admin alternate-cluster-admin-user'

# switch to test user to be sure that default project admin policy works properly
new_kubeconfig="${workingdir}/tempconfig"
os::cmd::expect_success "oc config view --raw > $new_kubeconfig"
os::cmd::expect_success "oc login -u alternate-cluster-admin-user -p anything --config=${new_kubeconfig}"

# alternate-cluster-admin should default to having star rights, so he should be able to update his role to that
resourceversion=$(oc get  clusterrole/alternate-cluster-admin -o=jsonpath="{.metadata.resourceVersion}")
cp ${OS_ROOT}/test/fixtures/bootstrappolicy/alternate_cluster_admin.yaml ${workingdir}
os::util::sed "s/RESOURCE_VERSION/${resourceversion}/g" ${workingdir}/alternate_cluster_admin.yaml
os::cmd::expect_success "oc replace --config=${new_kubeconfig} clusterrole/alternate-cluster-admin -f ${workingdir}/alternate_cluster_admin.yaml"

# alternate-cluster-admin can restrict himself to no groups
resourceversion=$(oc get  clusterrole/alternate-cluster-admin -o=jsonpath="{.metadata.resourceVersion}")
cp ${OS_ROOT}/test/fixtures/bootstrappolicy/cluster_admin_without_apigroups.yaml ${workingdir}
os::util::sed "s/RESOURCE_VERSION/${resourceversion}/g" ${workingdir}/cluster_admin_without_apigroups.yaml
os::cmd::expect_success "oc replace --config=${new_kubeconfig} clusterrole/alternate-cluster-admin -f ${workingdir}/cluster_admin_without_apigroups.yaml"

# alternate-cluster-admin should NOT have the power add back star now
resourceversion=$(oc get  clusterrole/alternate-cluster-admin -o=jsonpath="{.metadata.resourceVersion}")
cp ${OS_ROOT}/test/fixtures/bootstrappolicy/alternate_cluster_admin.yaml ${workingdir}
os::util::sed "s/RESOURCE_VERSION/${resourceversion}/g" ${workingdir}/alternate_cluster_admin.yaml
os::cmd::expect_failure_and_text "oc replace --config=${new_kubeconfig} clusterrole/alternate-cluster-admin -f ${workingdir}/alternate_cluster_admin.yaml" "attempt to grant extra privileges"

echo "policy: ok"
