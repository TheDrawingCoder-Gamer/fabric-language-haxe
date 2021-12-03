package net.fabricmc.language.haxe;

/*
	Copyright 2021 BulbyVR

	 Licensed under the Apache License, Version 2.0 (the "License");
	 you may not use this file except in compliance with the License.
	 You may obtain a copy of the License at

		   http://www.apache.org/licenses/LICENSE-2.0

	 Unless required by applicable law or agreed to in writing, software
	 distributed under the License is distributed on an "AS IS" BASIS,
	 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	 See the License for the specific language governing permissions and
	 limitations under the License.
*/
import net.fabricmc.api.ModInitializer;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import net.fabricmc.loader.api.LanguageAdapter;
import net.fabricmc.loader.api.ModContainer;
import net.fabricmc.loader.launch.common.FabricLauncherBase;
import net.fabricmc.loader.api.LanguageAdapterException;
import java.lang.reflect.Modifier;
using Lambda;
/*
Tries to get around haxe jank by searching for haxe-ified class locations
Currently known renames:
Foo (with static fields) to _Foo.Foo_Fields_
private Foo to _Foo.Foo
That's all I could find for classes
Private Foo is private so we should NOT demangle it
Functions I am unsure about
@:generic exists but uh you shouldn't be using that, as java has real overload support
*/
@:nativeGen
class HaxeAdapter implements LanguageAdapter {
	public function new() {}
	@:throws(net.fabricmc.loader.api.LanguageAdapterException)
	// <T:Dynamic> pleases java gods somehow :sob:
	// It's a miracle I was able to write this in haxe
	public function create <T:Dynamic> (mod:ModContainer, value:String, type:java.lang.Class<T>):T {
		var methodSplit = value.split("::");
		while (methodSplit[methodSplit.length - 1] == "") {
			methodSplit.pop();
		}
		if (methodSplit.length >= 3) {
			throw new LanguageAdapterException("Invalid Handle Format: " + value);
		}
		var clazz:Null<java.lang.Class<Any>> = null;
		try {
			clazz = java.lang.Class.forName(methodSplit[0], true, FabricLauncherBase.getLauncher().getTargetClassLoader());
		} catch (e:java.lang.ClassNotFoundException) {
			// Try to get fields
			var clazzNameSplit = methodSplit[0].split(".");
			var clazzName = clazzNameSplit.pop();
			clazzName = "_" + clazzName + "." + clazzName + "_Fields_";
			clazzNameSplit.push(clazzName);
			try {
				clazz = java.lang.Class.forName(clazzNameSplit.join("."),true, FabricLauncherBase.getLauncher().getTargetClassLoader());
			} catch (e:java.lang.ClassNotFoundException) {
				// Couldn't find haxe name
				throw new LanguageAdapterException(e);
			} 
		}
		switch (methodSplit.length) {
			case 1: 
				if (type.isAssignableFrom(clazz)) {
					return clazz.getDeclaredConstructor().newInstance();
				} else {
					throw new LanguageAdapterException("Class " + clazz.getName() + " cannot be cast to " +  type.getName() + "!");
				}
			case 2: 
				// Field or Function access
				// From what I can tell we get a list because overloading
				var methodList = java.Lib.array(clazz.getDeclaredMethods()).filter((it) -> it.getName() == methodSplit[1]);

				try {
					var field = clazz.getDeclaredField(methodSplit[1]);
					var fType = field.getType();

					if ((field.getModifiers() & Modifier.STATIC) == 0) {
						throw new LanguageAdapterException("Field " + value + " cannot be static!");
					}
					if (methodList.length != 0) {
						throw new LanguageAdapterException("Ambiguous " + value + " - refers to field and method!");
					}
					if (!type.isAssignableFrom(fType)) {
						throw new LanguageAdapterException("Field " + value + " cannot be cast to " + type.getName() + "!");
					}
					return cast field.get(null);
				} catch (e:java.lang.NoSuchFieldException) {
					// do nothing
				} catch (e:java.lang.IllegalAccessException) {
					throw new LanguageAdapterException("Field " + value + " cannot be accessed!");
				}
				if (!type.isInterface()) {
					throw new LanguageAdapterException("Cannot proxy method " + value + " to non-interface type " + type.getName() + "!");
				}
				if (methodList.length == 0) {
					throw new LanguageAdapterException("Could not find " + value + "!");
				} else if (methodList.length >= 2) {
					throw new LanguageAdapterException("Can't access overloaded method " + value + "!");
				}

				final targetMethod = methodList[0];
				var obj:Dynamic = null;

				if ((targetMethod.getModifiers() & Modifier.STATIC) == 0) {
					try {
						obj = clazz.getDeclaredConstructor().newInstance();
					} catch (ex:java.lang.Exception) {
						throw new LanguageAdapterException(ex);
					}
				}

				var handle:java.lang.invoke.MethodHandle;

				try {
					handle = java.lang.invoke.MethodHandles.lookup().unreflect(targetMethod);
				} catch (ex:java.lang.Exception) {
					throw new LanguageAdapterException(ex);
				}

				try {
					return java.lang.invoke.MethodHandleProxies.asInterfaceInstance(type, handle);
				} catch (ex:java.lang.Exception) {
					throw new LanguageAdapterException(ex);
				}
			default: 
				throw new LanguageAdapterException("Invalid Handle Format: " + value);
		}
	}
}
