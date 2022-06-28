# Description

**Type:** Distributed
**Requires CredSSP:** No

This resource is responsible for creating Excel Services Application instances
within the local SharePoint farm. The resource will provision and configure the
Excel Services Service Application.

The default value for the Ensure parameter is Present. When not specifying this
parameter, the service application is provisioned.

Only SharePoint 2013 is supported to deploy Excel Services service applications via DSC,
as SharePoint 2016 and SharePoint 2019 have deprecated this service. See
[What's deprecated or removed from SharePoint Server 2016](https://docs.microsoft.com/en-us/SharePoint/what-s-new/what-s-deprecated-or-removed-from-sharepoint-server-2016)
for more info.
