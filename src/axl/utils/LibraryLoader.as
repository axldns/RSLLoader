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

	public class LibraryLoader
	{
		private var xfileName:String;
		private var rootObj:Object;
		private var isLocal:Boolean;
		private var classDict:Object;

		public var onReady:Function;
		public var libraryURLs:Object;
		private var libraryLoader:Loader;
		private var urlLoader:URLLoader;
		private var urlReq:URLRequest;
		private var URLIndex:int;
		private var context:LoaderContext;
		private var params:Object;
		private var lInfo:LoaderInfo;
		private var getStageTimeout:uint;
		protected var tname:String = '[LibraryLoader 0.0.1]';
		
		private var framesCounter:int;
		public var framesAwaitingLimit:int = 30;
		private var isLaunched:Boolean;
		public function LibraryLoader(rootObject:Object)
		{
			rootObj = rootObject;
			trace(tname, '[CONSTRUCTOR]Root:', rootObj, rootObj ? rootObj.loaderInfo : ':(');
		}
		public function get fileName():String { return xfileName}
		public function get classDictionary():Object { return classDict }
		public function load():void
		{
			if(libraryURLs==null || libraryURLs.length < 1)
				throw new Error("Set libraryURLs variable before loading");
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
			if(onReady)
				onReady();
		}
		
		private function getLibrary():void
		{
			URLIndex = -1;
			loadNext();
		}
		
		private function loadNext():void
		{
			if(++URLIndex < libraryURLs.length)
			{
				loadURL(libraryURLs[URLIndex]);
			}
			else
				trace(tname,"[CRITICAL ERROR] no alternative library paths last [APPLICATION FAIL]");
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
			var bytes:ByteArray =urlLoader.data;
			if(libraryLoader == null)
			{
				libraryLoader = new Loader();
				
				lInfo = libraryLoader.contentLoaderInfo;
				lInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onError);
				this.addListeners(lInfo,onLoaderComplete,onError);
					
				params = new Object();
				params.fileName = fileName;
				params.whatEver = "test";
				context = new LoaderContext(false);
				context.applicationDomain = new ApplicationDomain();
				context.allowCodeImport = true;
				context.parameters = params;
			}
			
			trace(tname,"[LOADED]", urlReq.url);
			libraryLoader.loadBytes(bytes, context);
		}
		
		private function onLoaderComplete(e:Event):void 
		{
			trace(tname, 'onLoaderComplete');
			mapClasses();
			destroy();
		}
		
		private function mapClasses():void
		{
			trace(tname, 'mapClasses');
			var an:Vector.<String> = libraryLoader.contentLoaderInfo.applicationDomain.getQualifiedDefinitionNames();
			var len:int = an.length;
			var n:String='';
			var cn:String;
			var cls:Class;
			var mapped:int = 0;
			if(!classDict)
				classDict = {}
			for(var i:int =0; i <len; i++)
			{
				cn = an[i];
				mapped++;
				try {
					cls = libraryLoader.contentLoaderInfo.applicationDomain.getDefinition(cn) as Class;
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
			trace(tname,"[MAPPED]", mapped, '/', len, 'Classes form loaded library ApplicationDomain');
			onReady();
		
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
		
		private function destroy():void
		{
			trace(tname, 'destroy');
			removeListeners(libraryLoader, onLoaderComplete, onError);
			removeListeners(urlLoader, onURLComplete, onError);
			libraryLoader = null;
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