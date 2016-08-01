[RSLLoader](http://axldns.com/docs/axl/utils/RSLLoader.html) - runtime shared library loader
---------

Helps you to load Runtime Shared Library from`libraryURLs` to the ApplicationDomain you specify in `domainType` via domain. 

It maps classes from loaded content to `classDictionary` assoc array. This allows to use these even if you decide to load your RSL to separated application domain, eg. to avoid class conflicts when different assets have different versions of the same framework embedded in.

It supports alternative directories to satisfy dispersed systems and fallbacks. 
There are two methodologies to pick from, controlled by `twoStepLoading` property:

- Two step loading - loads binary conent via URLLoader first, then loads from bytes with Loader (may help with security issues but flash vars are only "attempted" to pass (don't work according to documentation). Also supports loading from embedded assets (as class) and then first step is skipped.
- One Step Loading sorts everything in regular URLRequest passed to Loader but security errors are more likely to happen.

Once complete, executes instance.`onReady` callback if set.
Once `onReady` is called, you can access several properties of loaded content:

 - instance.`bytes`
 - instance.`libraryLoader`
 - instance.`classDictionary`
 - instance.`loadedContentLoaderInfo`


Context Parameters
------------------

All parameters from query in URL are stripped out from initial URL but stored. The only valid parameter for first step load is cachebust which can be controlled via useCachebust variable.

All parameters from inital query are passed to second step loading (from bytes) to loader context.

Additional parameters can be added to `contextParameters` property.
Automatically RSLLoader adds `fileName` parameter - file name of requester which is deducted as follows: 

 - REQUESTER.`loaderInfo.parameters.fileName` - the highest
 - REQUESTER.`loaderInfo.parameters.loadedUR`L - if fileName is not
   present, can be stripped out from this one. Additionally, loadedURL
   is going to be used as a prefix for relative addresses defined in
   libraryURLs. Good for changing relative paths context when loaded by
   another app.
 - REQUESTER.`loaderInfo.url` - if none of above is present, fileName is
   deducted from standard flash url property (which, due to security
   reasons, may not supply relevant information in nested structures).

FileName parameter is ideal for stubs of which name is meaningfull. 

Example
-------

    rslloader= new RSLLoader(this,trace);
    rslloader.domainType = rslloader.domain.separated;
    rslloader.libraryURLs = [serverURL,backupServerURL,local];
    rslloader.onReady = onProgramLoaded;
    rslloader.load();

AXL Library adhesion
--------------------
RSLLoader is valid part of AXL library. Since AXL library can be used as dynamically linked RSL, in many cases, keeping RSL away from Loader may be required.  They're separate repositories but same BSD license applies.
