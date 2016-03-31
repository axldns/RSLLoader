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

	/** This class loads anything you specify in <code>libraryURLs</code> to the ApplicationDomain you specify in <code>domainType</code> via <code>domain</code>
	 * <br> e.g. <code>instance.domainType = instance.domain.coppyOfCurrent</code><br>
	 * <br>Once ready it will execute <code>instance.onReady</code> callback if set.
	 *  <br>Once onReady is called, you can access several properties of loaded content<br>
	 * <ul>
	 * <li>instance.bytes</li>
	 * <li>instance.libraryLoader</li>
	 * <li>instance.classDictionary</li>
	 * <li>instance.loadedContentLoadderInfo</li>
	 * </ul>
	 * */
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
		private var xbytes:ByteArray;
		private var params:Object;
		private var lInfo:LoaderInfo;
		private var getStageTimeout:uint;
		protected var tname:String = '[LibraryLoader 0.0.15]';
		
		private var framesCounter:int;
		private var isLaunched:Boolean;
		private var xloadedContentLoadderInfo:LoaderInfo;
		private var xisLOADING:Boolean;
		private var xerror:Boolean;
		
		
		public var domain:DomainType = new DomainType();
		
		public var onReady:Function;
		public var libraryURLs:Object;
		public var framesAwaitingLimit:int = 30;
		public var getFromCurrentAppDomainIfPresent:Array;
		public var mapOnlyClasses:Array;
		/**
		 * Use <code>instance.domain</code> to set it. Eg.:<br>
		 * <code>instance.domainType = instance.domain.coppyOfCurrent</code><br>
		 * */
		public var domainType:Object = domain.coppyOfCurrent;
		public var contextParameters:Object;
		
		public var onNewVersion:Function;
		public var currentLibraryVersion:String;
		public var log:Function;
		public var handleUncaughtErrors:Boolean=true;
		public var stopErrorPropagation:Boolean=false;
		public var unloadOnErrors:Boolean=true;
		public var preventErrorDefaults:Boolean=true;
		
		/** @see LibraryLoader */
		public function LibraryLoader(rootObject:Object,loggingFunc:Function=null)
		{
			rootObj = rootObject;
			tname= rootObj+tname;
			log = loggingFunc || trace;
			
			log(tname, '[CONSTRUCTOR]', rootObj ? rootObj.loaderInfo : 'root Object lodaerInfo not available yet');
		}
		public function get loadedContentLoadderInfo():LoaderInfo { return xloadedContentLoadderInfo }
		public function get isLOADING():Boolean {return xisLOADING }
		public function get fileName():String { return xfileName}
		public function get classDictionary():Object { return classDict }
		public function get bytes():ByteArray {	return xbytes }
		public function get libraryLoader():Loader { return xlibraryLoader}
		public function get error():Boolean { return xerror }
		public function load():void
		{
			if(isLOADING)
				return;
			if(libraryURLs==null || libraryURLs.length < 1)
				throw new Error("Set libraryURLs variable before loading");
			xisLOADING = true;
			xerror = false;
			findFilename();
		}
		private function findFilename():void
		{
			log(tname + '[findFilename]');
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
					log(rootObj + ' loaderInfoAvailable=false', framesCounter, '/', framesAwaitingLimit);
				else
				{
					log(rootObj, framesCounter, '/', framesAwaitingLimit, 'limit reached. loaderInfo property not found. ABORT');
					rootObj.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
					isLaunched = false;
				}
			}
		}
		
		private function onLoaderInfoAvailable(e:Event=null):void
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
				mergeLoadedURLtoLibraryURLs(rootObj.loaderInfo.parameters.loadedURL.substr(0,rootObj.loaderInfo.parameters.loadedURL.lastIndexOf('/')+1));
			}
			if(rootObj.loaderInfo.parameters.fileName != null)
				xfileName = rootObj.loaderInfo.parameters.fileName;
			
			xfileName = fileName || rootObj.loaderInfo.parameters.fileName || fileNameFromUrl(rootObj.loaderInfo.url);
			log(tname +" fileName =", fileName, 'isLocal:', isLocal);
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
			log(tname,'[Merge library URLs]', this.libraryURLs);
		}
		
		private function fileNameFound():void
		{
			runApp();
		}
		
		private function runApp():void
		{
			try { Security.allowDomain("*"); }
			catch(e:*) { log(tname, e)};
			getLibrary();
		}
		
		private function run():void
		{
			if(!error)
				dealWithLoadedLibraryVersions();			
			if(onReady)
				onReady();
		}
		
		private function dealWithLoadedLibraryVersions():void
		{
			//log('dealWithLoadedLibraryVersions', libraryLoader, libraryLoader && libraryLoader.content ?  libraryLoader.content.hasOwnProperty('VERSION') : false);
			if(libraryLoader && libraryLoader.content && libraryLoader.content.hasOwnProperty('VERSION'))
			{
				var v:String = libraryLoader.content['VERSION']; 
				log(tname, '[VERSION of loaded library]:', v, '(against',currentLibraryVersion +')');
				if(currentLibraryVersion is String && (v != currentLibraryVersion))
				{
					log("..which is new comparing to", currentLibraryVersion);
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
				log("All classes found in current domain, no need to laod. Mapping");
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
			log(tname + '[READY]' + '['+xfileName+'][' + libraryURLs[URLIndex] + ']');
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
					log("LOADING FROM BYTES");
					
					loadFromBytes(new o);
				}
				else
				{
					log("UNKNOWN RESOURCE LISTED @ libraryURLs[", URLIndex, "]", flash.utils.describeType(o));
					loadNext();
				}
			}
			else
			{
				log(tname,"[CRITICAL ERROR] no alternative library paths last [APPLICATION FAIL]");
				xerror = true;
				finalize();
			}
		}
		private function loadURL(url:String):void
		{
			if(urlReq == null)
			{
				urlReq = new URLRequest();
			}
			urlReq.url = url + (isLocal ? "":'?caheBust=' + String(new Date().time));
			if(urlLoader == null)
			{
				urlLoader = new URLLoader();
				urlLoader.dataFormat = URLLoaderDataFormat.BINARY;
				addURLListeners(urlLoader,onURLComplete,onError);
			}
			log(tname,"[loading]",  urlReq.url);
			
			try { urlLoader.load(urlReq) }
			catch(e:Object) { log(tname, "ERROR", e) }
		}
		
		private function onHTTPStatus(e:Event):void { log(e) }
		private function onURLOpen(e:Event):void { log(e) }
		private function onProgress(e:Event):void { log(e) }		
		private function onURLComplete(e:Event):void
		{
			log(tname, '[URLload complete .. LOADING FROM BYTES]');
			xbytes =  urlLoader.data;
			loadFromBytes(xbytes);
		}
		
		private function loadFromBytes(ba:ByteArray):void
		{
			if(libraryLoader == null)
			{
				xlibraryLoader = new Loader();
				context = new LoaderContext(false);
				
				lInfo = libraryLoader.contentLoaderInfo;
				if(handleUncaughtErrors)
					lInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onError);
				this.addListeners(lInfo,onLoaderComplete,onError);
				
				log(tname,"setting context parameters");
				if(contextParameters != null)
				{
					params = contextParameters;
				}
				else
				{
					params  = { fileName : fileName };
				}
				
				if(domainType is ApplicationDomain)
				{
					context.applicationDomain = domainType as ApplicationDomain;
					log(tname,"LOADING TO SPECIFIC APPLICATION DOMAIN");
				}
				else
				{
					switch(domainType)
					{
						case domain.coppyOfCurrent:
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
			
			libraryLoader.loadBytes(ba, context);
		}
		
		private function onLoaderComplete(e:Event):void 
		{
			log(tname, '[LOADED!]onLoaderComplete');
			xloadedContentLoadderInfo = libraryLoader.contentLoaderInfo;
			finalize(libraryLoader.contentLoaderInfo.applicationDomain);
		}
		
		private function mapClasses(domain:ApplicationDomain):void
		{
			log(tname, 'mapClasses');
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
			log(tname,"[MAPPED]", mapped, '/', len, 'Classes form loaded library ApplicationDomain', mapped < len ? n :n);
		}
		
		private function onError(e:Object=null):void
		{
			log(tname,"[ERROR]");
			
			if(e && stopErrorPropagation && e.hasOwnProperty('stopImmediatePropagation'))
			{
				log(tname,'[stop error propagation]');
				e.stopImmediatePropagation();
			}
			if(e && preventErrorDefaults && e.hasOwnProperty('preventDefault'))
			{
				log(tname,'[prevent default error behavior]');
				e.preventDefault();
			}
			log(tname,"[CAN'T LOAD LIBRARY]", urlReq.url, "\n", e, e is Error ? Error(e).getStackTrace() : '');
			if(libraryLoader && unloadOnErrors)
			{
				log(tname,'[UNLOAD ..LOADING NEXT]');
				libraryLoader.unloadAndStop();
				loadNext();
			}
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
		
		private function addURLListeners(dispatcher:IEventDispatcher,onUrlLoaderComplete:Function,onError:Function):void
		{
			if(dispatcher == null)
			{
				log("URL DISPATCHER NOT DEFINED");
				return;
			}
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
		
		private function destroy(clearBytes:Boolean=false):void
		{
			log(tname, 'destroy');
			removeListeners(libraryLoader, onLoaderComplete, onError);
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
import flash.system.ApplicationDomain;

internal class DomainType {
	public const coppyOfCurrent:int = -1;
	public const current:int = 0;
	public const separated:int = 1;
	public const loaderOwnerDomain:int = 2;
	public const copyOfLoaderOwnerDomain:int = 3;
	public function specific(v:ApplicationDomain):ApplicationDomain { return v}
}