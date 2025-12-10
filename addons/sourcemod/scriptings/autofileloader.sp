#pragma semicolon 1
#pragma newdecls required

#define DEBUG 0 // 0 - выключено, 1 - включено
#define PLUGIN_DESCRIPTION "Automatically takes custom files and precaches them and adds them to the downloads table."
#define PLUGIN_VERSION "1.0.6"

#include <sourcemod>
#include <sdktools>

ConVar cvar_Status;
ConVar cvar_ConfigFile;

ArrayList array_Exclusions;
ArrayList array_Downloadables;

enum eLoad
{
	Load_Materials,
	Load_Models,
	Load_Sounds
}

public Plugin myinfo =
{
	name = "Auto File Loader",
	author = "Drixevel (updated for anonim)",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "https://drixevel.dev/"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	CreateConVar("sm_autofileloader_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, 
		FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);
	
	cvar_Status = CreateConVar("sm_autofileloader_status", "1", 
		"Status of the plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	cvar_ConfigFile = CreateConVar("sm_autofileloader_config", "configs/autofileloader_exclusions.txt", 
		"Text file with paths to exclude (one per line).", FCVAR_NOTIFY);

	array_Exclusions = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
	array_Downloadables = CreateArray(ByteCountToCells(6));
	
	// File extensions to process
	PushArrayString(array_Downloadables, ".vmt");
	PushArrayString(array_Downloadables, ".vtf");
	PushArrayString(array_Downloadables, ".vtx");
	PushArrayString(array_Downloadables, ".mdl");
	PushArrayString(array_Downloadables, ".phy");
	PushArrayString(array_Downloadables, ".vvd");
	PushArrayString(array_Downloadables, ".wav");
	PushArrayString(array_Downloadables, ".mp3");

	RegAdminCmd("sm_generateexternals", Command_GenerateExternals, ADMFLAG_ROOT);
	RegAdminCmd("sm_ge", Command_GenerateExternals, ADMFLAG_ROOT);
}

public void OnMapStart()
{
	if (!GetConVarBool(cvar_Status))
	{
		return;
	}

	LoadExclusions();
	StartProcess(false);
}

void StartProcess(bool print = false)
{
	AutoLoadDirectory(".", print);

	DirectoryListing dir = OpenDirectory("custom");
	if (dir != null)
	{
		FileType fType;
		char sPath[PLATFORM_MAX_PATH];

		while (ReadDirEntry(dir, sPath, sizeof(sPath), fType))
		{
			if (fType != FileType_Directory)
			{
				continue;
			}

			if (StrEqual(sPath, "workshop") || StrEqual(sPath, ".") || StrEqual(sPath, ".."))
			{
				continue;
			}

			char sBuffer[PLATFORM_MAX_PATH];
			Format(sBuffer, sizeof(sBuffer), "custom/%s", sPath);

			AutoLoadDirectory(sBuffer, print);
		}

		delete dir;
	}
}

bool AutoLoadDirectory(const char[] path, bool print = false)
{
	DirectoryListing dir = OpenDirectory(path);

	if (!dir)
	{
		return false;
	}

	char sPath[PLATFORM_MAX_PATH];
	FileType fType;

	while (ReadDirEntry(dir, sPath, sizeof(sPath), fType))
	{
		if (fType != FileType_Directory)
		{
			continue;
		}

		char sBuffer[PLATFORM_MAX_PATH];
		Format(sBuffer, sizeof(sBuffer), "%s/%s", path, sPath);

		if (IsPathExcluded(sBuffer))
		{
			//LogDebug("Skipping excluded directory: %s", sBuffer);
			continue;
		}

		if (StrEqual(sPath, "materials"))
		{
			AutoLoadFiles(sBuffer, path, Load_Materials, print);
		}
		else if (StrEqual(sPath, "models"))
		{
			AutoLoadFiles(sBuffer, path, Load_Models, print);
		}
		else if (StrEqual(sPath, "sound"))
		{
			AutoLoadFiles(sBuffer, path, Load_Sounds, print);
		}
	}

	delete dir;
	return true;
}

bool AutoLoadFiles(const char[] path, const char[] remove, eLoad load, bool print = false)
{
	//LogDebug("Loading Directory: %s - %s - %i", path, remove, load);
	LogDebug("Loading Directory: %s", path);

	DirectoryListing dir = OpenDirectory(path);

	if (!dir)
	{
		return false;
	}

	char sPath[PLATFORM_MAX_PATH];
	FileType fType;

	while (ReadDirEntry(dir, sPath, sizeof(sPath), fType))
	{
		if (StrEqual(sPath, "..") || StrEqual(sPath, "."))
		{
			continue;
		}

		char sBuffer[PLATFORM_MAX_PATH];
		Format(sBuffer, sizeof(sBuffer), "%s/%s", path, sPath);

		if (IsPathExcluded(sBuffer))
		{
			//LogDebug("Skipping excluded file/dir: %s", sBuffer);
			continue;
		}

		switch (fType)
		{
			case FileType_Directory:
			{
				AutoLoadFiles(sBuffer, remove, load, print);
			}

			case FileType_File:
			{
				bool isBZ2 = StrContains(sPath, ".bz2", false) != -1;
				bool isZTMP = StrContains(sPath, ".ztmp", false) != -1;
				
				if (isBZ2 || isZTMP)
				{
					//LogDebug("Skipping BZ2 file (handled by engine): %s", sBuffer);
					continue;
				}
				
				char sCleanPath[PLATFORM_MAX_PATH];
				strcopy(sCleanPath, sizeof(sCleanPath), sBuffer);
				
				if (StrContains(sCleanPath, "./") == 0)
				{
					RemoveFrontString(sCleanPath, sizeof(sCleanPath), 2);
				}
				else if (StrContains(sCleanPath, "custom/") == 0)
				{
					strcopy(sCleanPath, sizeof(sCleanPath), sCleanPath[7]);
				}
				
				bool isProcessableFile = false;
				for (int i = 0; i < GetArraySize(array_Downloadables); i++)
				{
					char sExtension[16];	// Можно [4]
					GetArrayString(array_Downloadables, i, sExtension, sizeof(sExtension));
					
					if (StrContains(sPath, sExtension) != -1)
					{
						isProcessableFile = true;
						break;
					}
				}
				
				if (!isProcessableFile)
				{
					continue;
				}
				
				LogDebug("Processing file: %s", sBuffer);

				if (print)
				{
					char sLogPath[PLATFORM_MAX_PATH];
					BuildPath(Path_SM, sLogPath, sizeof(sLogPath), "logs/autofileloader.generate.log");
					
					File file = OpenFile(sLogPath, "a");
					if (file != null)
					{
						WriteFileLine(file, "%s", sCleanPath);
						delete file;
					}
				}
				
				if (!print)
				{
					AddFileToDownloadsTable(sCleanPath);
					
					switch (load)
					{
						case Load_Materials:
						{
							if (StrContains(sPath, "decals") != -1 && StrContains(sPath, ".vmt") != -1)
							{
								LogDebug("");
								LogDebug("Precaching Decal: %s", sCleanPath);
								LogDebug("");
								PrecacheDecal(sCleanPath);
							}
						}

						case Load_Models:
						{
							if (StrContains(sPath, ".mdl") != -1)
							{
								LogDebug("");
								LogDebug("Precaching Model: %s", sCleanPath);
								LogDebug("");
								PrecacheModel(sCleanPath);
							}
						}

						case Load_Sounds:
						{
							if (StrContains(sPath, ".wav") != -1 || StrContains(sPath, ".mp3") != -1)
							{
								LogDebug("");
								LogDebug("Precaching Sound: %s", sCleanPath);
								LogDebug("");
								ReplaceString(sCleanPath, sizeof(sCleanPath), "sound/", "");
								PrecacheSound(sCleanPath);
							}
						}
					}
				}
			}
		}
	}

	delete dir;
	return true;
}

bool IsPathExcluded(const char[] path)
{
	char sCheckPath[PLATFORM_MAX_PATH];
	
	if (IsPathInExclusions(path))
		return true;
	
	strcopy(sCheckPath, sizeof(sCheckPath), path);
	if (strlen(sCheckPath) > 2 && sCheckPath[0] == '.' && sCheckPath[1] == '/')
	{
		RemoveFrontString(sCheckPath, sizeof(sCheckPath), 2); // Remove "./"
	}
	
	if (IsPathInExclusions(sCheckPath))
		return true;
	
	if (StrContains(sCheckPath, "custom/") == 0)
	{
		strcopy(sCheckPath, sizeof(sCheckPath), sCheckPath[7]); // Remove "custom/"
		if (IsPathInExclusions(sCheckPath))
			return true;
	}
	
	return false;
}

bool IsPathInExclusions(const char[] path)
{
	for (int i = 0; i < GetArraySize(array_Exclusions); i++)
	{
		char sExclude[PLATFORM_MAX_PATH];
		GetArrayString(array_Exclusions, i, sExclude, sizeof(sExclude));
		
		if (strlen(sExclude) == 0 || sExclude[0] == '#' || 
			(strlen(sExclude) >= 2 && sExclude[0] == '/' && sExclude[1] == '/'))
			continue;
		
		TrimString(sExclude);
		
		if (StrContains(path, sExclude, false) != -1)
		{
			return true;
		}
	}
	
	return false;
}

void LoadExclusions()
{
	ClearArray(array_Exclusions);
	
	char sConfigPath[PLATFORM_MAX_PATH];
	GetConVarString(cvar_ConfigFile, sConfigPath, sizeof(sConfigPath));
	
	char sFullPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFullPath, sizeof(sFullPath), sConfigPath);
	
	LogDebug("Loading exclusions from: %s", sFullPath);
	
	char sDirPath[PLATFORM_MAX_PATH];
	GetDirFromPath(sFullPath, sDirPath, sizeof(sDirPath));
	if (!DirExists(sDirPath))
	{
		CreateDirectory(sDirPath, 511);
	}
	
	File file = OpenFile(sFullPath, "r");
	if (file == null)
	{
		file = OpenFile(sFullPath, "w");
		if (file != null)
		{
			WriteFileLine(file, "# Auto File Loader - Exclusions File");
			WriteFileLine(file, "# Add one path per line to exclude");
			WriteFileLine(file, "# Lines starting with # or // are comments");
			WriteFileLine(file, "");
			WriteFileLine(file, "# Examples:");
			WriteFileLine(file, "# models/props/cs_office/offinspamdl.mdl");
			WriteFileLine(file, "# models/props/cs_office/");
			WriteFileLine(file, "# models/props/");
			WriteFileLine(file, "# materials/unwanted/");
			WriteFileLine(file, "# sound/vo/");
			WriteFileLine(file, "");
			WriteFileLine(file, "# Add your exclusions below:");
			WriteFileLine(file, "models/props");
			
			delete file;
			
			LogDebug("Created default exclusions file");
		}
		return;
	}
	
	char sLine[PLATFORM_MAX_PATH];
	while (!file.EndOfFile() && file.ReadLine(sLine, sizeof(sLine)))
	{
		TrimString(sLine);
		
		if (strlen(sLine) == 0 || sLine[0] == '#' || 
			(strlen(sLine) >= 2 && sLine[0] == '/' && sLine[1] == '/'))
			continue;
		
		int commentPos = StrContains(sLine, " //");
		if (commentPos != -1)
		{
			sLine[commentPos] = '\0';
			TrimString(sLine);
		}
		
		if (strlen(sLine) > 0)
		{
			PushArrayString(array_Exclusions, sLine);
			//LogDebug("Added exclusion: %s", sLine);
		}
	}
	
	delete file;
	
	LogDebug("Loaded %d exclusions", GetArraySize(array_Exclusions));
}

void GetDirFromPath(const char[] path, char[] buffer, int maxlength)
{
	strcopy(buffer, maxlength, path);
	
	int pos = -1;
	for (int i = strlen(buffer) - 1; i >= 0; i--)
	{
		if (buffer[i] == '/' || buffer[i] == '\\')
		{
			pos = i;
			break;
		}
	}
	
	if (pos != -1)
	{
		buffer[pos] = '\0';
	}
	else
	{
		buffer[0] = '\0';
	}
}

stock void RemoveFrontString(char[] strInput, int iSize, int iVar)
{
	strcopy(strInput, iSize, strInput[iVar]);
}

stock void LogDebug(const char[] format, any ...)
{
    #if DEBUG == 1
    char sBuffer[1024];
    VFormat(sBuffer, sizeof(sBuffer), format, 2);
    
    char sLogPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sLogPath, sizeof(sLogPath), "logs/autofileloader.debug.log");
    
    File file = OpenFile(sLogPath, "a");
    if (file != null)
    {
        if (strlen(sBuffer) == 0)
        {
            WriteFileLine(file, "");
        }
        else
        {
            WriteFileLine(file, "%s", sBuffer);
        }
        delete file;
    }
    #else
    #pragma unused format
    #endif
}

public Action Command_GenerateExternals(int client, int args)
{
	LoadExclusions();
	
	char sLogPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sLogPath, sizeof(sLogPath), "logs/autofileloader.generate.log");
	
	File file = OpenFile(sLogPath, "w");
	if (file != null)
	{
		delete file;
	}
	
	StartProcess(true);
	
	int fileCount = 0;
	file = OpenFile(sLogPath, "r");
	if (file != null)
	{
		char sLine[256];
		while (!file.EndOfFile() && file.ReadLine(sLine, sizeof(sLine)))
		{
			TrimString(sLine);
			if (strlen(sLine) > 0)
			{
				fileCount++;
			}
		}
		delete file;
	}
	
	ReplyToCommand(client, "[Auto File Loader] Generation complete. %d files found.", fileCount);
	
	return Plugin_Handled;

}
