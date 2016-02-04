package axl.utils
{
	import flash.display.Loader;
	import flash.display.LoaderInfo;
	import flash.events.Event;
	import flash.events.IEventDispatcher;
	import flash.events.IOErrorEvent;
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

	public class LibraryLoader
	{
		private var xfileName:String;
		private var rootObj:Object;
		private var isLocal:Boolean;
		private var classDict:Object;

		private var xlibraryLoader:Loader;
		private var urlLoader:URLLoader;
		private var urlReq:URLRequest;
		private var URLIndex:int;
		private var context:LoaderContext;
		private var params:Object;
		private var lInfo:LoaderInfo;
		private var getStageTimeout:uint;
		protected var tname:String = '[LibraryLoader 0.0.4]';
		
		private var framesCounter:int;
		private var isLaunched:Boolean;
		private var xloadedContentLoadderInfo:LoaderInfo;
		private var xisLOADING:Boolean;
		
		public function get bytes():ByteArray {	return xbytes }
		public function get libraryLoader():Loader { return xlibraryLoader}


		public var onReady:Function;
		public var libraryURLs:Object;
		public var framesAwaitingLimit:int = 30;
		public var getFromCurrentAppDomainIfPresent:Array;
		public var mapOnlyClasses:Array;
		/** Loads library to specific application domain according the rule:
		 * <ul>
		 * <li><b>negative values</b> (default): new ApplicationDomain(ApplicationDomain.currentDomain) - This allows the loaded SWF file to use the parent's classes directly, 
		 * for example by writing new MyClassDefinedInParent(). The parent, however, cannot use this syntax; if the parent wishes 
		 * to use the child's classes, it must call ApplicationDomain.getDefinition() to retrieve them. The advantage of this choice is that, 
		 * if the child defines a class with the same name as a class already defined by the parent, no error results; the child simply 
		 * inherits the parent's definition of that class, and the child's conflicting definition goes unused unless either child or parent 
		 * calls the ApplicationDomain.getDefinition() method to retrieve it.</li>
		 * <li><b>0 value</b>: ApplicationDomain.currentDomain - When the load is complete, parent and child can use each other's classes directly.
		 * If the child attempts to define a class with the same name as a class already defined by the parent, the parent class is used and the child class is ignored.
		 * <li><b>positive values</b>: new ApplicationDomain(null) - This separates loader and loadee entirely, allowing them to define separate versions of classes 
		 * with the same name without conflict or overshadowing. The only way either side sees the other's classes is by calling the ApplicationDomain.getDefinition() method.</li>
		 * </ul>
		 * */
		public var domainType:int = -1;
		private var xbytes:ByteArray;
		public var onNewVersion:Function;
		public var currentLibraryVersion:String;
		
		public function LibraryLoader(rootObject:Object)
		{
			rootObj = rootObject;
			trace(tname, '[CONSTRUCTOR]Root:', rootObj, rootObj ? rootObj.loaderInfo : ':(');
		}
		public function get loadedContentLoadderInfo():LoaderInfo { return xloadedContentLoadderInfo }
		public function get isLOADING():Boolean {return xisLOADING }
		public function get fileName():String { return xfileName}
		public function get classDictionary():Object { return classDict }
		public function load():void
		{
			if(isLOADING)
				return;
			if(libraryURLs==null || libraryURLs.length < 1)
				throw new Error("Set libraryURLs variable before loading");
			xisLOADING = true;
			findFilename();
		}
		private function findFilename():void
		{
			trace(tname + '[findFilename]');
			if(loaderInfoAvailable)
				onLoaderInfoAvailable();
			else
				rootObj.addEventListener(Event.ENTER_FRAME, onEnterFrame);
		}
		private function get loaderInfoAvailable():Boolean { return rootObj.loaderInfo && rootObj.loaderInfo.url }
		
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
					trace(rootObj + ' loaderInfoAvailable=false', framesCounter, '/', framesAwaitingLimit);
				else
				{
					trace(rootObj, framesCounter, '/', framesAwaitingLimit, 'limit reached. loaderInfo property not found. ABORT');
					rootObj.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
					isLaunched = false;
				}
			}
		}
		
		private function onLoaderInfoAvailable(e:Event=null):void
		{
			trace(tname + '[onLoaderInfoAvailable]');
			trace(tname + ' loaderInfo',rootObj.loaderInfo);
			trace(tname + ' loaderInfo.url',rootObj.loaderInfo.url);
			trace(tname + ' loaderInfo.parameters.fileName',rootObj.loaderInfo.parameters.fileName);
			trace(tname + ' loaderInfo.parameters.loadedURL',rootObj.loaderInfo.parameters.loadedURL);
			isLocal = rootObj.loaderInfo.url.match(/^(file|app):/i);
			
			if(rootObj.loaderInfo.parameters.loadedURL != null)
			{
				xfileName = fileNameFromUrl(rootObj.loaderInfo.url,true);
				mergeLoadedURLtoLibraryURLs(rootObj.loaderInfo.parameters.loadedURL.substr(0,rootObj.loaderInfo.parameters.loadedURL.lastIndexOf('/')+1));
			}
			if(rootObj.loaderInfo.parameters.fileName != null)
				xfileName = rootObj.loaderInfo.parameters.fileName;
			
			xfileName = fileName || rootObj.loaderInfo.parameters.fileName || fileNameFromUrl(rootObj.loaderInfo.url);
			trace(tname +" fileName =", fileName, 'isLocal:', isLocal);
			fileNameFound()
		}
		
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
			trace(tname,'[MERGED] library URLs', this.libraryURLs);
		}
		
		private function fileNameFound():void
		{
			runApp();
		}
		
		private function runApp():void
		{
			try { Security.allowDomain("*"); }
			catch(e:*) { trace(tname, e)};
			getLibrary();
		}
		
		private function run():void
		{
			trace(tname, '[READY]');
			dealWithLoadedLibraryVersions();			
			if(onReady)
				onReady();
		}
		
		private function dealWithLoadedLibraryVersions():void
		{
			trace('dealWithLoadedLibraryVersions', libraryLoader, libraryLoader.content ?  libraryLoader.content.hasOwnProperty('VERSION') : false);
			if(libraryLoader && libraryLoader.content && libraryLoader.content.hasOwnProperty('VERSION'))
			{
				var v:String = libraryLoader.content['VERSION']; 
				trace(tname, '[VERSION of loaded library]:', v, '(against',currentLibraryVersion +')');
				if(currentLibraryVersion is String && (v != currentLibraryVersion))
				{
					trace("..which is new comparing to", currentLibraryVersion);
					if(onNewVersion is Function)
						onNewVersion(v);
					if(libraryLoader.content.hasOwnProperty('onVersionUpdate') && libraryLoader.content['onVersionUpdate'] is Function)
						libraryLoader.content['onVersionUpdate'](v);
				}
			}
		}
		
		private function getLibrary():void
		{
			var foundAll:Boolean;
			if(getFromCurrentAppDomainIfPresent&& getFromCurrentAppDomainIfPresent.length > 0)
			{
				var cn:int;
				var cdc:Vector.<String> = ApplicationDomain.currentDomain.getQualifiedDefinitionNames();
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
			if(foundAll)
			{
				trace("All classes found in current domain, no need to laod. Mapping");
				finalize(ApplicationDomain.currentDomain);
			}
			else
			{
				URLIndex = -1;
				loadNext();
			}
		}
		
		private function finalize(domain:ApplicationDomain=null):void
		{
			domain ? mapClasses(domain) : null
			xisLOADING = false;
			run();
			destroy();
		}
		
		private function loadNext():void
		{
			if(++URLIndex < libraryURLs.length)
			{
				var o:* =libraryURLs[URLIndex];
				if(o is String)
					loadURL(o);
				else if(o is Class)
				{
					trace("LOADING FROM BYTES");
					
					loadFromBytes(new o);
				}
				else
				{
					trace("UNKNOWN RESOURCE LISTED @ libraryURLs[", URLIndex, "]", flash.utils.describeType(o));
					loadNext();
				}
				
			}
			else
			{
				trace(tname,"[CRITICAL ERROR] no alternative library paths last [APPLICATION FAIL]");
				finalize();
			}
		}
		
		private function loadURL(url:String):void
		{
			if(urlReq == null)
			{
				urlReq = new URLRequest();
			}
			urlReq.url = url + '?caheBust=' + String(new Date().time);
			trace(tname,"[loading]",  urlReq.url );
			if(urlLoader == null)
			{
				urlLoader = new URLLoader(urlReq);
				urlLoader.dataFormat = URLLoaderDataFormat.BINARY;
				addListeners(urlLoader,onURLComplete,onError);
			}
			urlLoader.load(urlReq);
		}
		
		private function onURLComplete(e:Event):void
		{
			xbytes =  urlLoader.data;
			loadFromBytes(xbytes);
		}
		
		private function loadFromBytes(ba:ByteArray):void
		{
			if(libraryLoader == null)
			{
				xlibraryLoader = new Loader();
				
				lInfo = libraryLoader.contentLoaderInfo;
				lInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onError);
				this.addListeners(lInfo,onLoaderComplete,onError);
				
				params = new Object();
				params.fileName = fileName;
				params.whatEver = "test";
				context = new LoaderContext(false);
				if(domainType < 0)
				{
					context.applicationDomain = new ApplicationDomain(ApplicationDomain.currentDomain);
					trace(tname,"LOADING TO COPY OF CURRENT APPLICATION DOMAIN (loaded content can use parent classes, parent can't use childs classes other way than via class dict)")
				}
				else if(domainType > 0 )
				{
					context.applicationDomain = new ApplicationDomain(null);
					trace(tname,"LOADING TO BRAND NEW APPLICATION DOMAIN (loaded content can't use parent's classes, parent can't use childs classes other way than via class dict. Watch your fonts.")
				}
				else if(domainType == 0)
				{
					context.applicationDomain = ApplicationDomain.currentDomain;
					trace(tname,"LOADING TO CURRENT APPLICATION DOMAIN (all shared, conflicts may occur)")
				}
				context.allowCodeImport = true;
				context.parameters = params;
			}
			
			trace(tname,"[LOADED]", libraryURLs[URLIndex]);
			libraryLoader.loadBytes(ba, context);
		}
		
		private function onLoaderComplete(e:Event):void 
		{
			trace(tname, 'onLoaderComplete');
			xloadedContentLoadderInfo = libraryLoader.loaderInfo;
			finalize(libraryLoader.contentLoaderInfo.applicationDomain);
		}
		
		private function mapClasses(domain:ApplicationDomain):void
		{
			trace(tname, 'mapClasses');
			var limited:Boolean = mapOnlyClasses is Array;
			var targ:Object = limited ? mapOnlyClasses : domain.getQualifiedDefinitionNames();
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
					classDict[cn] = cls;
					n+='\n'+i+': '+cn;
					
				}
				catch(e:*)
				{
					n+= '\n' + cn + " can not be included" +  e;
					mapped--;
				}
			}
			trace(tname,"[MAPPED]", mapped, '/', len, 'Classes form loaded library ApplicationDomain', mapped < len ? n :"");
		}
		
		private function onError(e:*=null):void
		{
			trace(tname,"[CAN'T LOAD LIBRARY]", urlReq.url, "\n", e);
			if(libraryLoader)
			{
				libraryLoader.unload();
				libraryLoader.unloadAndStop();
			}
			loadNext();
		}
		
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
		
		private function destroy(clearBytes:Boolean=false):void
		{
			trace(tname, 'destroy');
			removeListeners(libraryLoader, onLoaderComplete, onError);
			removeListeners(urlLoader, onURLComplete, onError);
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
		}
		
		
		public static function fileNameFromUrl(v:String,removeQuerry:Boolean=false,removeExtension:Boolean=false):String
		{
			var fileName:String = v||"";
			var q:int = fileName.indexOf('?');
			if(q > -1&&removeQuerry)
				fileName = fileName.substr(0,q).split('/').pop();
			else
				fileName = fileName.split('/').pop();
			return removeExtension ? fileName.replace(/.\w+$/i, "") : fileName;
		}
	}
}