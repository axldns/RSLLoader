/**
 *
 * AXL Library
 * Copyright 2014-2016 Denis Aleksandrowicz. All Rights Reserved.
 *
 * This program is free software. You can redistribute and/or modify it
 * in accordance with the terms of the accompanying license agreement.
 *
 */
package axl.utils
{
	import flash.display.Loader;
	import flash.display.LoaderInfo;
	import flash.events.Event;
	import flash.events.HTTPStatusEvent;
	import flash.events.IEventDispatcher;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.UncaughtErrorEvent;
	import flash.net.URLLoader;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.system.ApplicationDomain;
	import flash.system.LoaderContext;
	import flash.system.Security;
	import flash.utils.ByteArray;
	import flash.utils.describeType;

	/** This class loads anything you specify in <code>libraryURLs</code> to the ApplicationDomain you specify in
	 * <code>domainType</code> via <code>domain</code>. <br><br>
	 * 
	 * It maps classes from loaded content to <code>classDictionary</code> assoc array. This allows to use them even if you decide
	 * to load your RSL to separated application domain, eg. to avoid class conflicts when different assets have different 
	 * versions of the same framework embedded in.<br><br>
	 * 
	 * It supports alternative directories to satisfy dispersed systems and fallbacks.
	 * <br>There are two methodologies 
	 * to pick from, controlled by <code>twoStepLoading</code> property:<br><br>
	 * <i>Two step loading</i> - loads binary conent via URLLoader first, then loads from bytes with Loader 
	 * (may help with security issues but flash vars are only "attempted" to pass* (don't work according to documentation).
	 * Also supports loading from  embedded assets (as class) and then first step is skipped.<br>
	 * <i>One Step Loading</i> in the other hand, sorts everything in regular URLRequest passed to Loader but security errors are more likely to happen.<br>
	 * <br>
	 * Once loaded, executes <code>instance.onReady</code> callback if set.<br>
	 * Once onReady is called, you can access several properties of loaded content
	 * <ul>
	 * <li>instance.bytes</li>
	 * <li>instance.libraryLoader</li>
	 * <li>instance.classDictionary</li>
	 * <li>instance.loadedContentLoaderInfo</li>
	 * </ul>
	 * <h1>Context Parameters</h1>
	 * All parameters from query in URL are stripped out from initial URL but stored. The only valid parameter for first step
	 * load is cachebust which can be controlled via <code>useCachebust</code> variable.<br>
	 * All parameters from inital query are passed to second step loading (from bytes) to loader context.<br>
	 * Additional parameters can be added to <code>contextParameters</code> property.<br>
	 * Automatically RSLLoader adds fileName parameter - file name of requester which is deducted as follows:
	 * <ul>
	 * <li>REQUESTER.loaderInfo.parameters.fileName - the highest</li>
	 * <li>REQUESTER.loaderInfo.parameters.loadedURL - if fileName is not present, can be stripped out from this one. Additionally, loadedURL
	 * is going to be used as a prefix for relative addresses defined in libraryURLs. Good for changing relative paths context when loaded by another app.</li>
	 * <li>REQUESTER.loaderInfo.url - if none of above is present, fileName is deducted from standard flash url property (which,
	 *  due to security reasons, may not supply relevant information in nested structures). </li>
	 * </ul>
	 * FileName parameter is ideal for stubs of which name is meaningfull. 
	 * <h4>Example</h4>
	 * <pre>rslloader = new RSLLoader(this);<br>rslloader.domainType = rslloader.domain.separated;<br>rslloader.libraryURLs = newVersion ? [net,local] : [local,net];<br>rslloader.onReady = onProgramLoaded;<br>rslloader.load();</pre>
	 * */
	public class RSLLoader
	{
		protected var tname:String = '[RSLLoader 0.0.20]';
		private var rootObj:Object;
		private var classDict:Object;
		
		private var xlibraryLoader:Loader;
		private var urlLoader:URLLoader;
		private var urlReq:URLRequest;
		private var URLIndex:int;
		private var xloadedContentLoaderInfo:LoaderInfo;
		private var lInfo:LoaderInfo;
		
		private var context:LoaderContext;
		private var paramsFromQuery:Array=[];
		private var params:Object;
		private var xbytes:ByteArray;
		private var xfileName:String;
		
		private var framesCounter:int;
		
		private var isLocal:Boolean;
		private var xisLOADING:Boolean;
		private var xerror:Boolean;
		
		/** Allows to pick ApplicationDomain to which loaded content is going to be put s*/
		public var domain:DomainType = new DomainType();
		
		/** Callback to fire when content is loaded. It does fire even if error occured,as in this case, all alternative directiries were checked
		 * and there's nothing else to do. */
		public var onReady:Function;
		
		/** Array or vector of URLs String or other resources (alternative directions) to load content from. Highest priority has items on index 0. 
		 * If assets from there are inaccessible and result in error, head moves to index 1 and continues loading. Once one element is loaded, queue does
		 * not continue loading other listed elements. This is a concept of alternative directories rather than multi assets loader.  */
		public var libraryURLs:Object;
		
		/** Determines how many frames application should wait if load requester (your parent swf) loaderInfo is not available. */
		public var framesAwaitingLimit:int = 30;
		
		/** List classes you need from the resource you're trying to load, and RSLLoader will check if by any chance they're available in current 
		 * application domain already, so loading external file may not be needed. This happens e.g. when multiple assets are trying to load same library. */
		public var getFromCurrentAppDomainIfPresent:Array;
		
		/** Limit contents of your classDictionary for advanced distribution. If not defined - all classes available in loaded SWF will be mapped */
		public var mapOnlyClasses:Array;
		
		/** Domain to which loaded content is going to be put. 
		 * Use <code>instance.domain</code> to set it. Eg.:<br>
		 * <code>instance.domainType = instance.domain.copyOfCurrent</code><br> */
		public var domainType:Object = domain.copyOfCurrent;
		
		/** Additional parameters to pass to loader context, aside from the one which were included in query string */
		public var contextParameters:Object;
		
		/** Function to log progress of RSLLoader. Must accept any arguments of any type, e.g. trace*/
		public var log:Function;
		
		/** Determines if any uncaught, async errors from loaded content should be intercepted. If <code>unloadOnErrors=true</code> - 
		 * it may unload contents half way through. Requires attention. @default false*/
		public var handleUncaughtErrors:Boolean=false;
		
		/** Determines if errors whilst loading should be stopped in propagation and its default behavior prevented. 
		 * If <code>handleUncaughtErrors=true</code> - applies also to errors during runtime. */
		public var stopErrorBehaviors:Boolean=false;
		
		/** Determines if after errors whilst loading, content should be unloaded. 
		 * If <code>handleUncaughtErrors=true</code> - applies also to errors during runtime. */
		public var unloadOnErrors:Boolean=true;
		
		/** Determines if RSL swf should be loaded fresh every time (true) or can be cached one (false)*/
		public var useCachebust:Boolean=true;
		
		/** Determines if data is first loaded through URLLoader in binary form and then from bytes (allows to cheat Sandbox, but flashVars 
		 * are not passed), or data is loaded directly from Loader (Security issues may occur but flashVars are passed) */
		public var twoStepLoading:Boolean = true;
		private var loaderTrace:String;
		
		/** @see LibraryLoader 
		 * @param rootObject any display object that belongs to your parent swf
		 * @param loggingFunc - function that accepts any number of parameters of any type, e.g. trace */
		public function RSLLoader(rootObject:Object,loggingFunc:Function=null)
		{
			rootObj = rootObject;
			tname= rootObj+tname;
			log = loggingFunc || recordToString;
			
			log(tname, '[CONSTRUCTOR]', rootObj ? rootObj.loaderInfo : 'root Object lodaerInfo not available yet');
		}
		
		/** Object LoaderInfo associated to newly loaded content. Available only <code>onReady</code> was fired and no error occured */
		public function get loadedContentLoaderInfo():LoaderInfo { return xloadedContentLoaderInfo }
		
		/** Returns false from instantiation until call <code>load()</code> and after <code>onReady</code>, true during loading*/
		public function get isLOADING():Boolean {return xisLOADING }
		
		/** Returns file name of loaded content*/
		public function get fileName():String { return xfileName}
		
		/** Once content is loaded, all classes from its application domain are mapped to classDictionary object. Class names without package
		 * are used as a key. Eg. flash.display::Sprite would be accessible as classDict.Sprite */
		public function get classDictionary():Object { return classDict }
		
		/** If load process is two step (first binary (URLLoader), second from bytes (Loader)), bytes property holds bytes associated with 
		 * first loader. This property is cleared right after calling <code>onReady</code> callback. */
		public function get bytes():ByteArray {	return xbytes }
		
		/** Retruns second step Loader - object used to load content from bytes. */
		public function get libraryLoader():Loader { return xlibraryLoader}
		
		/** Since <code>onReady</code> callback is called regardless if loading was successfull or not, use this property to check it. */
		public function get error():Boolean { return xerror }
		
		/** Once all properties are set, call load method to start loading. 
		 * If RSLLoader is used only to load class definitions, before loading external asset, RSLLoader can check current application domain
		 * for presence of this classes. If they're found there - no loading is needed. 
		 * @see #getFromCurrentAppDomainIfPresent */
		public function load():void
		{
			if(isLOADING)
				return;
			if(requestedClassesExistInCurrentAppDomain())
			{
				finalize(ApplicationDomain.currentDomain) // 4
				return;
			}
			if(libraryURLs==null || libraryURLs.length < 1)
				throw new Error(tname + "Set libraryURLs variable before loading");
			xisLOADING = true;
			xerror = false;
			findFilename(); //1
		}
		/** 1.<br>
		 * Tries to establish file name of load REQUESTER. It's going to be passed in parameters for loading REQUESTED file.
		 * Checks for loader info presence or waits <code>framesAwaitingLimit</code> for it.*/
		private function findFilename():void
		{
			log(tname + '[findFilename]');
			if(!loaderInfoAvailable) // 1.a
				rootObj.addEventListener(Event.ENTER_FRAME, onEnterFrame); // 1.1
			else
				onLoaderInfoAvailable(); // 1.2
		}
		
		/** 1.a<br>
		 * Checks if loader info url is present in requester */
		private function get loaderInfoAvailable():Boolean { return rootObj.loaderInfo && rootObj.loaderInfo.url }
		
		/** 1.1<br>
		 * Checks if loader info url is present in requester. Calls <code>onLoaderInfoAvailable</code> if present. Goes to dead end 
		 * if framesCounter reaches framesAwaiting limit. */
		private function onEnterFrame(e:*=null):void
		{
			if(loaderInfoAvailable)
			{
				rootObj.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
				onLoaderInfoAvailable()
			}
			else
			{
				if(++framesCounter < framesAwaitingLimit)
					log(rootObj + ' loaderInfoAvailable=false', framesCounter, '/', framesAwaitingLimit);
				else
				{
					log(rootObj, framesCounter, '/', framesAwaitingLimit, 'limit reached. loaderInfo property not found. ABORT');
					rootObj.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
					xisLOADING = false;
					framesCounter = 0;
				}
			}
		}
		
		/** 1.2<br>
		 * Parses loaderInfo of REQUESTER to determine its file name. Calls <code>fileNameFound</code> when ready.
		 * <h4>Priorities</h4>
		 * <ul>
		 * <li>REQUESTER.loaderInfo.parameters.fileName - the highest</li>
		 * <li>REQUESTER.loaderInfo.parameters.loadedURL - if fileName is not present, can be stripped out from this one. Additionally, loadedURL
		 * is going to be used as a prefix for relative addresses defined in libraryURLs. Good for changing relative paths context when loaded by another app.</li>
		 * <li>REQUESTER.loaderInfo.url - if none of above is present, fileName is deducted from standard flash url property (which,
		 *  due to security reasons, may not supply relevant information in nested structures). </li>
		 * </ul> */
		protected function onLoaderInfoAvailable(e:Event=null):void
		{
			log(tname + '[onLoaderInfoAvailable]');
			log(tname + ' loaderInfo',rootObj.loaderInfo);
			log(tname + ' loaderInfo.url',rootObj.loaderInfo.url);
			log(tname + ' loaderInfo.parameters.fileName',rootObj.loaderInfo.parameters.fileName);
			log(tname + ' loaderInfo.parameters.loadedURL',rootObj.loaderInfo.parameters.loadedURL);
			isLocal = rootObj.loaderInfo.url.match(/^(file|app).*:/i);
			
			if(rootObj.loaderInfo.parameters.loadedURL != null)
			{
				xfileName = fileNameFromUrl(rootObj.loaderInfo.url,true);
				mergeLoadedURLtoLibraryURLs(rootObj.loaderInfo.parameters.loadedURL.substr(0,rootObj.loaderInfo.parameters.loadedURL.lastIndexOf('/')+1));//1.2.1
			}
			if(rootObj.loaderInfo.parameters.fileName != null)
				xfileName = rootObj.loaderInfo.parameters.fileName;
			
			xfileName = fileName || rootObj.loaderInfo.parameters.fileName || fileNameFromUrl(rootObj.loaderInfo.url,true);
			log(tname +" fileName =", fileName, 'isLocal:', isLocal);
			fileNameFound(); //1.3
		}
		
		/** 1.2.1 If libraryURLs are relative, prefixes them with given value, changing original context when loaded by another app. */
		private function mergeLoadedURLtoLibraryURLs(v:String):void
		{
			for(var i:int = 0; i <  this.libraryURLs.length; i++)
			{
				var s:String = libraryURLs[i];
				if(s.match(/^(\.\.\/|\/.\.\/)/))
				{
					libraryURLs[i] = v + libraryURLs[i];
				}
			}
			log(tname,'[Merge library URLs]', this.libraryURLs);
		}
		
		/** 1.3<br>
		 * Tries to set up secure domain. Calls actual <code>getLibrary</code> function*/
		private function fileNameFound():void
		{
			try { Security.allowDomain("*"); }
			catch(e:*) { log(tname, e)};
			getLibrary(); //2
		}
		
		/** 2<br>
		 * If library is used only to load class definitions, before loading external asset, RSLLoader can check current application domain
		 * for presence of this classes. If they're found - no loading is needed*/
		protected function getLibrary():void
		{
			URLIndex = -1;
			loadNext(); // 2.1 
		}
		
		/** 2.1<br>
		 * Attempts to load next available resource specified in libraryURLs.
		 * <ul>
		 * <li>If it's string - treats it as an URL address and goes to first step load (binary) or one step loading.</li>
		 * <li>If resource is class (eg. embed swf) - instantiates it and goes to second step of loading - load from bytes.</li>
		 * <li>In case resource is neither string nor class, resource is skipped, loadNext directive is called.</li>
		 * </ul>
		 * If there are no more available resources and this method was called - that means loading was unsuccessful. Error is set to true,
		 * finalize is called. */
		protected function loadNext():void
		{
			if(++URLIndex < libraryURLs.length)
			{
				var o:* =libraryURLs[URLIndex];
				if(o is String)
					twoStepLoading ? loadWithTwoStepLoader(o) : loadWithOneStepLoader(o); // 2.1.1, 2.1.2
				else if(o is Class)
				{
					log(tname,"LOADING FROM BYTES");
					loadFromBytes(new o); //3
				}
				else
				{
					log(tname,"UNKNOWN RESOURCE LISTED @ libraryURLs[", URLIndex, "]", flash.utils.describeType(o));
					loadNext();
				}
			}
			else
			{
				log(tname,"[CRITICAL ERROR] no alternative library paths last [APPLICATION FAIL]");
				xerror = true;
				finalize(); // 4
			}
		}
		
		
		/** 2.1.1<br>
		 * Takes off all query strings (and stores it for later use), adds cache bust if set and requests 
		 * resource to load from URL in BINARY data format.*/
		private function loadWithTwoStepLoader(url:String):void
		{
			if(urlReq == null)
				urlReq = new URLRequest();
			
			urlReq.url = stripParamsFromQuery(url) + ((isLocal||!useCachebust) ? "":'?cacheBust=' + String(new Date().time));
			if(urlLoader == null)
			{
				urlLoader = new URLLoader();
				urlLoader.dataFormat = URLLoaderDataFormat.BINARY;
				addURLListeners(urlLoader,onURLComplete,onError); // 2.1.2, 3a
			}
			log(tname, "[two step loader, step1] loading directive passed.:", urlReq.url);
			try { urlLoader.load(urlReq) }
			catch(e:Object) { log(tname, "ERROR", e) }
		}
		
		private function onHTTPStatus(e:Event):void { log(e) }
		private function onURLOpen(e:Event):void { log(e) }
		private function onProgress(e:Event):void { log(e) }
		
		/** 2.1.2 References bytes to bytes property and passes it to loading step two - loadFromBytes*/
		private function onURLComplete(e:Event):void
		{
			log(tname, '[URLload complete .. LOADING FROM BYTES]');
			xbytes =  urlLoader.data;
			loadFromBytes(xbytes); // 3
		}
		
		/** 3. Loading step two. Uses byte array to load content. 
		 * <ul>
		 * <li>Sets up loader context:<br>parameters (including reviously stored from query string and deducted fileName)<br>
		 * applicationDomain: result of setting domainType property</li>
		 * <li>Listens for uncaught errors if set</li>
		 * <li>Sets up event listeners and requests load</li>
		 * </ul> Calls <code>onFromBytesComplete</code> on success, or on fail: <code>onError</code> */
		private function loadFromBytes(ba:ByteArray):void
		{
			if(libraryLoader == null)
			{
				setupLoaderContext();
			}
			try {
				libraryLoader.loadBytes(ba, context);
				log(tname, "loading directive passed. Bytes:", ba.length);
			} catch(e:*) { onError(e) }
		}
		
		private function loadWithOneStepLoader(o:String):void
		{
			if(urlReq == null)
				urlReq = new URLRequest();
			urlReq.url = urlReq.url = stripParamsFromQuery(o) + ((isLocal||!useCachebust) ? "":'?cacheBust=' + String(new Date().time));
			
			if(libraryLoader == null)
				setupLoaderContext();
			
			xlibraryLoader.load(urlReq, context);
			log(tname, "[one step loader] loading directive READY.:", urlReq.url);
		}
		
		private function setupLoaderContext():void
		{
			xlibraryLoader = new Loader();
			context = new LoaderContext(false);
			
			lInfo = libraryLoader.contentLoaderInfo;
			if(handleUncaughtErrors)
				lInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onError);
			this.addListeners(lInfo,onLoadersComplete,onError); // 3.1, 3a
			
			// CONTEXT PARAMS
			if(contextParameters != null)
				params = contextParameters;
			else
				params = {};
			params.fileName = fileName;
			includeQueryParams(params);
			var p:String = '';
			for(var s:String in params)
			{
				var par:String = String(params[s] is String ? params[s] : JSON.stringify(params[s]));
				p += s + ":" + par+ "\n";
				params[s] = par;
			}
			log(tname,"Loading with params:\n"+p);
			// DOMAIN
			if(domainType is ApplicationDomain)
			{
				context.applicationDomain = domainType as ApplicationDomain;
				log(tname,"LOADING TO SPECIFIC APPLICATION DOMAIN");
			}
			else
			{
				switch(domainType)
				{
					case domain.copyOfCurrent:
						context.applicationDomain = new ApplicationDomain(ApplicationDomain.currentDomain);
						log(tname,"LOADING TO COPY OF CURRENT APPLICATION DOMAIN (loaded content can use parent classes, parent can't use childs classes other way than via class dict)")
						break;
					case domain.current:
						context.applicationDomain = ApplicationDomain.currentDomain;
						log(tname,"LOADING TO CURRENT APPLICATION DOMAIN (all shared, conflicts may occur)");
						break;
					case domain.separated:
						context.applicationDomain = new ApplicationDomain(null);
						log(tname,"LOADING TO BRAND NEW APPLICATION DOMAIN (loaded content can't use parent's classes, parent can't use childs classes other way than via class dict. Watch your fonts.");
						break;
					case domain.loaderOwnerDomain:
						context.applicationDomain = rootObj.loaderInfo.applicationDomain;
						log(tname,"LOADING TO loaderOwnerDomain DOMAIN.");
						break;
					case domain.copyOfLoaderOwnerDomain:
						context.applicationDomain = new ApplicationDomain(rootObj.loaderInfo.applicationDomain);
						log(tname,"LOADING TO copyOfLoaderOwnerDomain DOMAIN.");
						break;
					default:
						context.applicationDomain =  lInfo.applicationDomain;
						log(tname,"LOADING TO loadee application domain?");
						break
				}
			}
			
			context.allowCodeImport = true;
			context.parameters = params;
		}
		
		/** 3.1<br>
		 * Called after successful second step load. Assigns contentLoaderInfo and calls finalize. */
		private function onLoadersComplete(e:Event):void 
		{
			log(tname, '[LOADED!]onLoaderComplete');
			xloadedContentLoaderInfo = libraryLoader.contentLoaderInfo;
			finalize(libraryLoader.contentLoaderInfo.applicationDomain); // 4
		}
		/** 3a Can be called from both URLLoader and Loader event listeners. Stops error propagation if set and requests 
		 * next / alternative resource location load. */
		protected function onError(e:Object=null):void
		{
			log(tname,"[ERROR]");
			
			if(e && stopErrorBehaviors && e.hasOwnProperty('preventDefault'))
			{
				e.stopImmediatePropagation();
				e.preventDefault()
			}
			log(tname,"[CAN'T LOAD LIBRARY]", urlReq.url, "\n", e, e is Error ? Error(e).getStackTrace() : '');
			log(tname,'[UNLOAD ..LOADING NEXT]');
			if(libraryLoader&&unloadOnErrors )
				libraryLoader.unloadAndStop();
			loadNext(); // 2.1
		}
		
		/** 4<br>
		 * Called when loading from bytes is complete. Request classes mapping from given domain, calls <code>onReady()</code> 
		 * and auto destroys instance */
		private function finalize(domain:ApplicationDomain=null):void
		{
			log(tname + '[READY]' + '['+xfileName+'][' + libraryURLs[URLIndex] + ']');
			domain ? mapClasses(domain) : null // H1
			xisLOADING = false;
			if(onReady != null)
				onReady();
			destroy(); // 5
		}
		
		// -------------------- FLOW  ---------------------- //
		// -------------------- HELPERS  ---------------------- //
		
		/** H1<br>
		 * Puts classes available in given application domain to <code>classDict</code> associative array where shortened class name
		 * is key and particular class is value. All classes are mapped if <code>mapOnlyClasses</code> array is not defined, or
		 * maps only classes which names do match values specified in that array. */
		private function mapClasses(domain:ApplicationDomain):void
		{
			var limited:Boolean = mapOnlyClasses is Array;
			var targ:Object = limited ? mapOnlyClasses : domain['getQualifiedDefinitionNames']();
			var len:int = limited ? mapOnlyClasses.length : targ.length;
			var n:String='';
			var cn:String;
			var cls:Class;
			var mapped:int = 0;
			if(!classDict)
				classDict = {};
			
			for(var i:int =0; i <len; i++)
			{
				cn = targ[i];
				mapped++;
				try {
					cls = domain.getDefinition(cn) as Class;
					
					cn = cn.substr(cn.lastIndexOf(':')+1);
					if(classDict[cn] is Class)
						n+= "DUPILCATE CLASS NAME ["+cn+"]";
					classDict[cn] = cls;
					n+='\n'+i+': '+cn;
					
				}
				catch(e:*)
				{
					n+= '\n' + cn + " can not be included" +  e;
					mapped--;
				}
			}
			log(tname,"[MAPPED]", mapped, '/', len, 'Classes form loaded library ApplicationDomain', mapped < len ? n :n);
		}
		/** H2<br>
		 * Checks if all classes specified in getFromCurrentAppDomainIfPresent are available for mapping from current ApplicationDomain. 
		 * Returns false if getFromCurrentAppDomainIfPresent is not defined. Called right before load directives. */
		private function requestedClassesExistInCurrentAppDomain():Boolean
		{
			var foundAll:Boolean=false;
			if(getFromCurrentAppDomainIfPresent is Array && getFromCurrentAppDomainIfPresent.length > 0)
			{
				var cn:int;
				var cdc:Vector.<String> = ApplicationDomain.currentDomain['getQualifiedDefinitionNames']();
				for(var i:int = 0, j:int = getFromCurrentAppDomainIfPresent.length; i <j;i++)
				{
					cn = cdc.indexOf(getFromCurrentAppDomainIfPresent[i]);
					if(cn < 0)
					{
						foundAll = false;
						break;
					}
					else
						foundAll = true;
				}
			}
			return foundAll;
		}
		/** 5<br>
		 * Destroys an instance. Removes event listeners from both loaders and loader info uncaught error event listener, clears
		 * bytes from binary loader, nulls out loaders. */
		protected function destroy(clearBytes:Boolean=false):void
		{
			log(tname, 'destroy');
			removeListeners(libraryLoader, onLoadersComplete, onError);
			removeURLListeners(urlLoader, onURLComplete, onError);
			//libraryLoader;
			if(bytes && clearBytes)
			{
				bytes.clear();
				xbytes = null;
			}
			urlLoader = null;
			if(lInfo)
				lInfo.uncaughtErrorEvents.removeEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onError);
			lInfo = null;
			this.loaderTrace = null;
		}
		
		// -------------------- EVENT LISTENERS ---------------------- //
		
		private function addListeners(dispatcher:IEventDispatcher,onUrlLoaderComplete:Function,onError:Function):void
		{
			if(dispatcher == null) return;
			dispatcher.addEventListener(IOErrorEvent.IO_ERROR, onError);
			dispatcher.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);
			dispatcher.addEventListener(Event.COMPLETE, onUrlLoaderComplete);
		}
		
		private function removeListeners(dispatcher:IEventDispatcher,onUrlLoaderComplete:Function,onError:Function):void
		{
			if(dispatcher == null) return;
			dispatcher.removeEventListener(IOErrorEvent.IO_ERROR, onError);
			dispatcher.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);
			dispatcher.removeEventListener(Event.COMPLETE, onUrlLoaderComplete);
		}
		
		private function addURLListeners(dispatcher:IEventDispatcher,onUrlLoaderComplete:Function,onError:Function):void
		{
			if(dispatcher == null) return;
			dispatcher.addEventListener(Event.COMPLETE, onUrlLoaderComplete);
			dispatcher.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, onHTTPStatus);
			dispatcher.addEventListener(HTTPStatusEvent.HTTP_STATUS, onHTTPStatus);
			dispatcher.addEventListener(IOErrorEvent.IO_ERROR, onError);
			dispatcher.addEventListener(Event.OPEN, onURLOpen);
			dispatcher.addEventListener(ProgressEvent.PROGRESS, onProgress);
			dispatcher.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);
		}
		
		private function removeURLListeners(dispatcher:IEventDispatcher,onUrlLoaderComplete:Function,onError:Function):void
		{
			if(dispatcher == null) return;
			dispatcher.removeEventListener(Event.COMPLETE, onUrlLoaderComplete);
			dispatcher.removeEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, onHTTPStatus);
			dispatcher.removeEventListener(HTTPStatusEvent.HTTP_STATUS, onHTTPStatus);
			dispatcher.removeEventListener(IOErrorEvent.IO_ERROR, onError);
			dispatcher.removeEventListener(Event.OPEN, onURLOpen);
			dispatcher.removeEventListener(ProgressEvent.PROGRESS, onProgress);
			dispatcher.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);
		}
		// -------------------- EVENT LISTENERS ---------------------- //
		
		// -------------------- URL TOOLS ---------------------- //
		/** Takes querry string from given url and stores key-values in <code>paramsFromQuery</code> variable.
		 * Returns url without query string. */
		private function stripParamsFromQuery(url:String):String
		{
			paramsFromQuery =[];
			var q:int = url.indexOf('?');
			if(q < 0) return url;
			paramsFromQuery = url.substr(q+1).split(/[&=]/);
			url =  url.substr(0,q);
			return url;
		}
		
		/** Fills up <code>params</code> assoc. array used for loader context parameters in loading from bytes process/ */
		private function includeQueryParams(params:Object):void
		{
			while(paramsFromQuery.length)
				params[paramsFromQuery.shift()] = paramsFromQuery.shift();
		}
		
		/** Returns filename from given url */
		public static function fileNameFromUrl(url:String,removeQuerry:Boolean=false,removeExtension:Boolean=false):String
		{
			var fileName:String = url||"";
			var q:int = fileName.indexOf('?');
			if(q > -1&&removeQuerry)
				fileName = fileName.substr(0,q).split('/').pop();
			else
				fileName = fileName.split('/').pop();
			return removeExtension ? fileName.replace(/.\w+$/i, "") : fileName;
		}
		// -------------------- URL TOOLS ---------------------- //
		/** Default log function. Access contents of recorded log via <code>recordedLog</code>*/
		public function recordToString(...args):void
		{
			var v:Object;
			var s:String='';
			for(var i:int = 0; i < args.length; i++)
			{
				v = args[i];
				if(v == null)
					s += 'null';
				else
					s += v.toString();
				if(args.length - i > 1)
					s += ' ';
			}
			s += '\n';
			loaderTrace += s;
		}
		
		/** Unless other logging function is passed to constructor, RSLLoader logs its progress 
		 * to string. Access this property to get it. Property is cleared during destroy (after onReady is fired). */
		public function get recordedLog():String { return loaderTrace }
	}
}
import flash.system.ApplicationDomain;

internal class DomainType {
	public const copyOfCurrent:int = -1;
	public const current:int = 0;
	public const separated:int = 1;
	public const loaderOwnerDomain:int = 2;
	public const copyOfLoaderOwnerDomain:int = 3;
	public function specific(v:ApplicationDomain):ApplicationDomain { return v}
}