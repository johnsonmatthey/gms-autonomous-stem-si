// Zaeem Najeeb @ Johnson Matthey Technology Centre, University of Oxford
// Liam Spillane @ Gatan Inc.
// Date: 04/06/2025
// version:20250604, v1.0

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// 			USER Global Parameters
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Boolean constants
number TRUE 				= 1
number FALSE 				= 0

number DO_CUSTOM_SCAN       = TRUE     // Requires DigiScan3
number DO_QUANTIFICATION    = FALSE    // Requires having a saved quant setup from the Quantification panel
string QUANT_SETUP_NAME     = "MySetup"    // Change to the name of the quantification element selection that has been saved in DM

// 2D Array Acquisition Parameters - change as appropriate
number SCAN_DWELL_TIME_SEC      = 0.001   // Pixel dwell time in seconds for 2D array scans
number SCAN_SELECTED_SIGNALS    = 2       // enabled scan signal channel - Confirm per microscope
number SCAN_NUM_FRAMES          = 1       // Number of passes per 2D array

// Output SI workspace prefix
string SI_DATA_PREFIX = "EELS_SI"


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// 			Program Global Parameters
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Python filename
string PY_FILENAME 				= "2DArray_PSD.py"

//Persistent notes for hybrid script sharing
string PERSISTENT_ROOT_TAG      = "SIMA"                              // parent tag group
string PERSISTENT_FILEPATH_TAG  = PERSISTENT_ROOT_TAG + ":Filepath"          // sharing working dir to .py script
string PERSISTENT_SURVEYID_TAG  = PERSISTENT_ROOT_TAG + ":SurveyImageID"     // sharing survey id to .py script
string PERSISTENT_TEMPERATURE_TAG = PERSISTENT_ROOT_TAG + ":Temperature"     // sharing temp in dC to .py script
string PERSISTENT_SCANDIR_TAG    = PERSISTENT_ROOT_TAG + ":ScanOutputDir"    // sharing scan output dir to .py script
string PERSISTENT_SCANPREFIX_TAG = PERSISTENT_ROOT_TAG + ":ScanOutputPrefix" // sharing scan filename prefix to .py script
string PERSISTENT_PSDFILENAME_TAG = PERSISTENT_ROOT_TAG + ":PSDFilename"     // sharing PSD tag filename to .py script

// Scan box save locations
string SCAN_OUTPUT_SUBDIR	= "ArbitraryScan"       // Subfolder of the working dir where scan taglists are written
string SCAN_OUTPUT_DIR                              // Will be same as the selected working directory defined by user
string SCAN_OUTPUT_PREFIX	= "scanlist"            // prefix for subscan filenames
string PSD_TAGFILE_NAME	    = "SIMA_PSD"            // This stores the scan box coords as taggroup file = don't include .gtg as auto added

// Quantification setup - needs SI names
string HL_image_name        = "EELS HL SI" // Change as appropriate
string LL_image_name        = "EELS LL SI" // Change as appropriate
string COLLATE_AFTER_ACQ_TAG = "SI:Acquisition:Preferences:Compound Documents:Use" // Check if SI acquisition is collated, as this must be off if doing quantification


// FOR USES WITH PYJEM, Otherwise do not use. Assume a PyJEM server is listening and triggers upon command 'df_autofocus'
void JEOL_autofocus(number sync){
	// 0 for synchronous (blocking) and 1 for asynchronous
	// ASSUMES PyJEM is running and listening on port 8099, localhost
	string pyScript = ""
	pyScript += "# Python Script for sending commands to PyJEM"+ "\n"
	pyScript += "import socket" + "\n"
	pyScript += "server_address = ('127.0.0.1', 8099)" + "\n"
	pyScript += "try:" + "\n"
	pyScript += "	with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client_socket:" + "\n"
	pyScript += "		client_socket.settimeout(10)" + "\n"
	pyScript += "		client_socket.connect(server_address)" + "\n"
	pyScript += "		message = 'df_autofocus'" + "\n"
	pyScript += "		client_socket.sendall(message.encode())" + "\n"
	pyScript += "		response = client_socket.recv(1024).decode()" + "\n"
	pyScript += "		print(f'Received from server: {response}')" + "\n"
	pyScript += "except Exception as e:" + "\n"
	pyScript += "	print('Failed to connect - no autfocus atempted' + str(e))" + "\n"
	
	ExecutePythonScriptString( pyScript, sync ) //change to 0 for synchronous
}

number FindImageByTitle(string ImageName, number imageaction, image &myimage)
{
    // http://www.dmscripting.com/files/Function_Find_Image_By_Title.s from D. R. G. Mitchell.

	// make sure the closeshoworhide variable is an integer between 0 and 2
	imageaction=round(imageaction)
	if(imageaction<0) imageaction=0
	if(imageaction>3) imageaction=3
	
	// Count the number of displayed images
	number nowins=countdocumentwindowsoftype(5)
	number i
	documentwindow thiswin
	// Get the title of the window. This is problem in that the 
	// title also contains the frame identifier eg A: My Name. 
	// The A:_ is removed to excise the name
	for(i=nowins-1; i>-1; i--)
		{
			thiswin=getnthdocumentwindowoftype(5,i)
			string wintitle=thiswin.windowgettitle()
			number dobreak=0
			// Identify the first space in the title. This occurs
			// after the A:_ part. Everything to the right of this
			// is retained as the image name
			number strlen=len(wintitle)
			number j
			for(j=0; j<strlen; j++)
				{
					string thischar=mid(wintitle, j, 1)
					if(thischar==" ") 
						{
							j=j+1
							dobreak=1
							break
						}
				}
			// Excise the title and compare with the passed in
			// string
			
			string finaltitle=mid(wintitle, j, strlen-j)

			// If a match is found, close the image and return 1
			if(finaltitle==ImageName)
				{					
					if(imageaction==0) windowclose(thiswin, 0)
					if(imageaction==1) windowselect(thiswin)
					if(imageaction==2) windowhide(thiswin)
					If(imageaction==3) windowselect(thiswin)//then do nothing - the function returns the image by reference anyway
					
					// Source the imagedocument from the window, and from that the image
					// The image is returned by reference					
					imagedocument myimgdoc= ImageWindowGetImageDocument( thiswin) 
					myimage:=myimgdoc.imagedocumentgetimage(0)
					return 1
				}
		}
	// No match was found, return 0 and make an image variable returned by reference with a value of -1
	// The function has to return a valid image - so this just avoids an error. The function will return
	// 0 in this case, so the main script can easily deal with the image not being found.
	myimage=realimage("", 4, 256,256)
	myimage=-1
	result("\n failed to find")
	return 0
}

Image get_EELS_spectrum(Image SI_data )
{
    // This function is called to create an EELS spectrum from an SI image
    // It returns the EELS spectrum image - NOTE that the tags to define an EELS spectrum change over time
    // The function assumes that the images provided are 3D SI data

    // Check if the images are 3D and get dimension sizes
    If (SI_data.ImageGetNumDimensions()!=3) Exit(0) 
    number size_dx, size_dy, size_dz
    size_dx = SI_data.ImageGetDimensionSize(0)
    size_dy = SI_data.ImageGetDimensionSize(1)
    size_dz = SI_data.ImageGetDimensionSize(2)

    // Calibration data form of SI
    number originz, scalez
    string unitsz, SI_name
    ImageGetDimensionCalibration(SI_data, 2,originz,scalez,unitsz,0)
    SI_name = GetName(SI_data)
    // Create a new image for the EELS spectrum - name it based on the SI image name
    Image EELS_spectra = realimage("Spectrum of " + SI_name, 4, size_dz)
    EELS_spectra.SetName("Spectrum of " + SI_name) // Set the name of the EELS spectrum image

    // Copy tags from the SI image to the EELS spectrum
    TagGroup sourcetags=imagegettaggroup(SI_data)
    TagGroup targettags=imagegettaggroup(EELS_spectra)
    taggroupcopytagsfrom(targettags,sourcetags)

    // Convert to EELS spectrum via updating tags appropriately
    // 1) Set Quant Results tag group
    targettags.TagGroupGetOrCreateTagGroup("Elemental Quantification:Quant Results")

    // 2) Set Meta Data tag group (Most important for EELS!) - NOTE older GMS use Spectrum Image instead of Spectrum
    string Meta_tag = "Meta Data"
    string Format = "Format"
    string SI = "Spectrum"
    TagGroup tg_Meta = targettags.TagGroupGetOrCreateTagGroup(Meta_tag)
    tg_Meta.TagGroupSetTagAsString(Format,SI)

    // 5) Retrieve UID and place it in the spectrum
    number UID0, UID1, UID2, UID3
    ImageGetUniqueID( SI_data ).GetValues(UID0, UID1, UID2, UID3)
    targettags.TagGroupSetTagAsLongRect( "Parent:Unique Image ID", UID0, UID1, UID2, UID3 )
    targettags.TagGroupSetTagAsString("Parent:Name", SI_name) // Set the parent name to the SI image name

    // 4) Store the ROI summing over in the Datapicker format too
    TagGroup tg_processing = NewTagList()
    TagGroup tg_data_picker = NewTagGroup()
    tg_data_picker.TagGroupSetTagAsString("Operation", "DataPicker")
    tg_data_picker.TagGroupSetTagAsLong("Parameters:End X", size_dx)
    tg_data_picker.TagGroupSetTagAsLong("Parameters:End Y", size_dy)
    tg_data_picker.TagGroupSetTagAsLong("Parameters:NPixels", size_dx*size_dy)
    tg_data_picker.TagGroupSetTagAsLong("Parameters:Start X", 0)
    tg_data_picker.TagGroupSetTagAsLong("Parameters:Start Y", 0)

    tg_data_picker.TagGroupSetTagAsString("Parent:Name", SI_name) // Set the parent name to the SI image name
    tg_data_picker.TagGroupSetTagAsLongRect("Parent:Unique Image ID", UID0, UID1, UID2, UID3 )

    tg_processing.TagGroupInsertTagAsTagGroup(0, tg_data_picker)
    // Now add to spectrum tags
    targettags.TagGroupGetOrCreateTagGroup("Processing")
    targettags.TagGroupSetTagAsTagGroup("Processing", tg_processing)

    // 5) Remove irrelevant tag groups (optional?)
    targettags.TagGroupDeleteTagWithLabel("SI")
    targettags.TagGroupDeleteTagWithLabel("Calibration")
    targettags.TagGroupDeleteTagWithLabel("DataBar")

    // Sum the data over the first two dimensions to create the EELS spectrum - Better via sliceN or slice3
    //result("\ndx:" + size_dx)
    //result(" dy:" + size_dy)
    //result(" dz:" + size_dz)
    for ( number py = 0; py < size_dy; py++ ){
        for ( number px = 0; px < size_dx; px++ ){
                EELS_spectra += SI_data.slice1( px, py, 0, 2, size_dz, 1 )
        }
    }
	number dispersion_cal = -1/IFGetActiveDispersion()
	ImageSetDimensionCalibration( EELS_spectra, 0, originz*dispersion_cal, scalez, "eV", 1 )
    ImageSetIntensityUnitInfo( EELS_spectra, "e-", 1 )
    EELS_spectra.ImageSetIntensityScale(SI_data.ImageGetIntensityScale() )
    EELS_spectra.ImageSetIntensityOrigin(SI_data.ImageGetIntensityOrigin() )
    EELS_spectra.ImageSetIntensityUnitString( SI_data.ImageGetIntensityUnitString() )

    return EELS_spectra
}

Image EELS_splice(Image HL_spectrum, Image LL_spectrum, number bad_channels, number overlap_channels )
{
    // This function is called to splice two EELS spectra together
    // It returns the spliced EELS spectrum image
    Image spliced_spectrum
    spliced_spectrum = EELSSpliceSpectrum(HL_spectrum, LL_spectrum, bad_channels, overlap_channels )

    // Copy tags from HL_spectrum to spliced_spectrum
    TagGroup HL_spec_tags=imagegettaggroup(HL_spectrum)
    TagGroup LL_spec_tags=imagegettaggroup(LL_spectrum)

    TagGroup targettags=imagegettaggroup(spliced_spectrum)
    taggroupcopytagsfrom(targettags,HL_spec_tags)

    spliced_spectrum.SetName("Spliced Spectrum")

    // Calibrate data from the LL_spectrum (oriinin shift should be zero loss shift)
    number originz, scalez
    string unitsz

    ImageGetDimensionCalibration( LL_spectrum, 0, originz, scalez, unitsz, 0)
	
	number dispersion_cal = -1/IFGetActiveDispersion()
	ImageSetDimensionCalibration( spliced_spectrum, 0, originz *dispersion_cal, scalez, "eV", 1 ) // Note the negative origin shift
    ImageSetIntensityUnitInfo( spliced_spectrum, "e-", 1 )
    // This would be same in both LL and HL spectra
    spliced_spectrum.ImageSetIntensityScale( LL_spectrum.ImageGetIntensityScale() )
    spliced_spectrum.ImageSetIntensityOrigin(LL_spectrum.ImageGetIntensityOrigin() )
    spliced_spectrum.ImageSetIntensityUnitString( LL_spectrum.ImageGetIntensityUnitString() )

	// // Set exposure as the lower value
	// number exposure_HL, exposure_LL
	// LL_spec_tags.TagGroupGetTagAsNumber("Acquisition:Parameters:Detector:exposure (s)",exposure_LL)
	// HL_spec_tags.TagGroupGetTagAsNumber("Acquisition:Parameters:Detector:exposure (s)",exposure_HL)
	
	// // Use the smaller value to be set in the tags
	// taggroup exposure_splice = targettags.TagGroupGetOrCreateTagGroup("EELS:Acquisition")
	// if (exposure_LL>exposure_HL){
	// 	exposure_splice.TagGroupSetTagAsLong("Exposure (s)",exposure_HL)
	// }
	// else{
	// 	exposure_splice.TagGroupSetTagAsLong("Exposure (s)",exposure_LL)
	// }

    return spliced_spectrum
}

void output_quant_results(TagGroup quant_edge){
	string element
	quant_edge.TagGroupGetTagAsString("Element", element)
	
	number areal_dens_val, areal_dens_std
	quant_edge.TagGroupGetTagAsDouble("Composition Info:Areal Dens (at./nm2):Value",areal_dens_val)
	quant_edge.TagGroupGetTagAsDouble("Composition Info:Cross-section (barns):Sigma",areal_dens_std)

	number cross_sect_val, cross_sect_std
	quant_edge.TagGroupGetTagAsDouble("Composition Info:Cross-section (barns):Value",cross_sect_val)
	quant_edge.TagGroupGetTagAsDouble("Composition Info:Cross-section (barns):Sigma",cross_sect_std)
	
	number vol_dens_val, vol_dens_std
	quant_edge.TagGroupGetTagAsDouble("Composition Info:Volumetric Dens (at./nm3):Value", vol_dens_val)
	quant_edge.TagGroupGetTagAsDouble("Composition Info:Volumetric Dens (at./nm3):Sigma", vol_dens_std)
	
	number prcnt_comp_val, prcnt_comp_std
	quant_edge.TagGroupGetTagAsDouble("Composition Info:Percent Composition (at.%):Value",prcnt_comp_val)
	quant_edge.TagGroupGetTagAsDouble("Composition Info:Percent Composition (at.%):Sigma",prcnt_comp_std)
	
	result("\n")
	result("\n Element: " + element)
	result("\n Areal Dens (at./nm2): " + areal_dens_val + ", STD: " + areal_dens_std)
	result("\n Cross-section (barns): " + cross_sect_val + ", STD: " + cross_sect_std)
	result("\n Volumetric Dens (at./nm3): " + vol_dens_val + ", STD: " + vol_dens_std)
	result("\n Percent Composition (at.%): " + prcnt_comp_val + ", STD: " + prcnt_comp_std)
	result("\n")	
}

taggroup LoadScanPointsFromFile(string fullpath){		
		taggroup scanList_TagList = newTagGroup()
		
		//fullpath+=".gtg"
		if(!(scanList_TagList.TagGroupLoadFromFile(fullpath))){
			Throw("Unable to find tag list file with specified path")
		}
		//scanList_TagList.TagGroupOpenBrowserWindow( 0 ) 
		//Add error checks here: 
		//	1) File validation
		//	2) File content validation. i.e. is the .gtg file a list of scan points	
		
		return scanList_TagList
	}

void Acquire2DArray_custom(number FOV_t,number FOV_l,number FOV_b,number FOV_r, number sizeX, number sizeY, string scan_num){
	image surveyImage := SIGetSurveyImage() // -------------ASSIGNED!

	// Create 2D ARRAY parameter set
	number paramID = SICreate2DArrayParameters( sizeX , sizeY , SCAN_DWELL_TIME_SEC , FOV_t , FOV_l , FOV_b , FOV_r )

	// Adjust paramater set
	// - Enabled the EELS signal
	number EELSindex = SIGetSignalIndex( paramID , "EELS" )
	if ( EELSIndex < 0) Throw( "EELS Signal not supported." )
	SISetSignalActive( paramID , EELSindex , TRUE )

	// - Enabled the EDS signal
	number EDSindex = SIGetSignalIndex( paramID , "EDS" )
	if ( 0 > EDSIndex ) Throw( "EDS Signal not supported." )
	SISetSignalActive( paramID , EDSindex , TRUE )
	
	// Set continuous drift correction
	SISetSurveyImage( paramID, surveyImage )
	SISetSpatialDriftCorrectionEnabled( paramID , TRUE )

	SISetSpatialDriftCorrectionDefaults( paramID )
	
	SISetSpatialDriftCorrectionAdvancedOptions(paramID, 1, 0) // 1 = do continuous, 0 = dont do predictive
	number periodUnit = 4        // 0 = MILLISECONDS, 1 = SECONDS, 2 = ROWS, 3 = PIXELS, 4 = FRAMES
	SISetSpatialDriftCorrectionFrequency( paramID, periodUnit, 1 )

	SISetSpatialDriftCorrectionDisplayOptions( paramID, TRUE, TRUE, 1)

	ROI driftROI = SIGetOrCreateSpatialDriftCorrectionROI( paramID )
	number surX,sury
	surveyImage.ImageGetDimensionSizes(surX,surY)
	driftROI.ROISetRectangle(surY*0.1,surX*0.1,surY*0.9,surX*0.9)
	SISetUseSurveyScanSignal( paramID )
	
	
	// - Enable scan signals (see SCAN_SELECTED_SIGNALS at top of file)
	SISetSelectedScanSignals( paramID, SCAN_SELECTED_SIGNALS )

	// - Do not show data during acquisition (=Default)
	SISetDisplayData( paramID , TRUE )

	// - Do not show prompts during acquisition (=Default)
	SISetAcquireSilently( paramID , TRUE )
	
	// - Do not show Live-data (=Default)
	SISetShowLiveSpectra( paramID , TRUE)

	// - Enable Sub-pixel Scan
	SISetSubPixelScanEnabled( paramID , FALSE )
	//SISetSubScanSize( paramID , 8 )
	//SISetDoSubScanMosaic( paramID , TRUE );
	
	// - Specify SW-sync pixel-iterator (Auto = Default)
	// 0 is hardware sync, 1 is software-sync. Note - custom scan does not work with software sync
	SISetPixelIterator( paramID , 0 )
	
	// - Specify number of passes (see SCAN_NUM_FRAMES at top of file)
	SISetNumPasses( paramID , SCAN_NUM_FRAMES )
				
	// Set custom scan points given you have DigiScan 3
	if (DO_CUSTOM_SCAN){
		//Filepath of scanlist taglist file	 
		string fullpath = SCAN_OUTPUT_DIR + SCAN_OUTPUT_PREFIX + scan_num + ".gtg"
		//Import scanlist from file and set custom scan points for SI capture
		TagGroup scanTags = LoadScanPointsFromFile(fullpath)
		SISetCustomScanPoints(paramID, 1, scanTags);		
	}

	// Perform acquisition 
	object dataList = SIAcquire( paramID )

	// Display data
	forEach( object o ; dataList )
	{
	o.GetContainerImage().ShowImage()
	}        
}


interface I_SIMultiAutomaton{
	object SIMA_init(object self, number waitTime_s, string fileName);
	void SIMA_Cleanup(object self);
	void pathToTags(object self);
	void SurveyIDToTagFile(object self);
	
	//SI Setup & Acquisition Functions
	image acquireDigiscanImage(object self);
	
	void SetupMultiPointFromTagList(object self);
	void SetupLineScanFromTagList(object self);
	void Setup2DArrayFromTagList(object self);
	
	//void SI_InitEELSEDS(object self);     assumed
	//void SI_IntiCBEDEDS(object self);		out of scope here
	
	void SI_MultiCapture(Object self);
	
	image OutputCurrentSurveyImage(object self);
	number OutputCurrentSurveyID(object self);
}

class C_SIMultiAutomaton:object{	
	image m_survey;
	number m_surveyID;
	number m_surveySizeX;
	number m_surveySizeY;
	number m_wsViewID;
	//number m_sizex; 	//size of what???
	//number m_sizey;
		
	number m_pixelTime_EELS_s;
	number m_SI_WaitTime_s;
	
	string m_filePath;
	string m_SIDataPath;
	string m_pyFilename;
	
	object SIMA_init(object self, number SI_WaitTime_s, string pyFilename){
		//m_sizex = 0;
		//m_sizey = 0;
		m_SI_WaitTime_s = SI_WaitTime_s
		m_pyFilename = pyFilename;
		
		return self;
	}
	
	void SIMA_CleanUp(object self){
		//Cleanup persistent notes at the end
		DeletePersistentNote(PERSISTENT_FILEPATH_TAG)
		DeletePersistentNote(PERSISTENT_SURVEYID_TAG)
		DeletePersistentNote(PERSISTENT_TEMPERATURE_TAG)
		DeletePersistentNote(PERSISTENT_SCANDIR_TAG)
		DeletePersistentNote(PERSISTENT_SCANPREFIX_TAG)
		DeletePersistentNote(PERSISTENT_PSDFILENAME_TAG)
		DeletePersistentNote(PERSISTENT_ROOT_TAG) //remove the now-empty parent tag group left behind by the notes above
	}
	
	void SetPathAndSerialise(object self){
		//Choose Path which must contain the gtg and the .py
		string SIMA_filepath
		if ( !GetDirectoryDialog( "Select folder to save tagfiles and py data. Must contain python files." , "" , SIMA_filepath ) ) 
			throw("Cannot proceed without valid folder path")
		
		//Fail fast if the chosen folder doesn't actually contain the python script
		if ( !DoesFileExist( SIMA_filepath + m_pyFilename ) )
			throw("Selected folder does not contain " + m_pyFilename)
		
		//Write to class members
		m_filePath = SIMA_filepath
		m_SIDataPath = SIMA_filepath + "SI_Data\\"
		
		//Test Paths
		result("\nSetPathandSerialise m_SIDataPath" + m_SIDataPath)
		result("\nSetPathAndSerialise m_filepath" + m_filePath)
		
		//Create SI Data Directory
		CreateDirectory(m_SIDataPath)
		
		//Create scan output directory as a subfolder of the working dir
		SCAN_OUTPUT_DIR = SIMA_filepath + SCAN_OUTPUT_SUBDIR + "/"
		CreateDirectory(SCAN_OUTPUT_DIR)
		
		//Create the PSD tag file if it doesn't already exist
		if ( !DoesFileExist( SIMA_filepath + PSD_TAGFILE_NAME + ".gtg" ) ){
			taggroup emptyPSDTagList = NewTagGroup()
			emptyPSDTagList.TagGroupSaveToFile(SIMA_filepath + PSD_TAGFILE_NAME)
		}
		
		//Share the working dir and scan output dir/prefix/PSD filename with the Python script via persistent tags
		SetPersistentStringNote(PERSISTENT_FILEPATH_TAG, SIMA_filepath)
		SetPersistentStringNote(PERSISTENT_SCANDIR_TAG, SCAN_OUTPUT_DIR)
		SetPersistentStringNote(PERSISTENT_SCANPREFIX_TAG, SCAN_OUTPUT_PREFIX)
		SetPersistentStringNote(PERSISTENT_PSDFILENAME_TAG, PSD_TAGFILE_NAME)
	}
	
	void surveyIDToTagFile(object self){
		SetPersistentNumberNote(PERSISTENT_SURVEYID_TAG, m_surveyID)
		
		//Validation
		number surveyID
		GetPersistentNumberNote(PERSISTENT_SURVEYID_TAG, surveyID)
		result("\n" + datestamp() + "\ttagpath = " + PERSISTENT_SURVEYID_TAG + "\n" + datestamp() + "\tvalue = " + surveyID)
	}
	
	void acquireDigiscanImage(object self){	
		DSInvokeButton( 1 )
		DSFinishAcquisition()
		
		m_wsViewID = WorkSpaceGetActive();
		
		DSWaitUntilFinished( ) 
		
		image img:= GetFrontImage()		//Change this section to be using param sets as well
		m_survey = img
		m_surveyID = img.getImageID()
		img.ImageGetDimensionSizes(m_surveySizeX, m_surveySizeY)
		result("\n" + datestamp() + "\t" + "internal ID = " + m_surveyID)
		// this might be better as a bool that throws an error if it doesn't work, then have separate function to export 
		// data after validation checks. 
	}
	
	void py_AnalyseSurveyImage(object self){
		string pyscriptfullpath = m_filepath + m_pyfilename
		
		string GMSVersion = GetApplicationVersionString()
		if(GMSVersion == "3.4")
		//Boolean logic for this function is inverted for GMS Version < 3.5.0
			executePythonScriptFile(pyscriptfullpath, TRUE)
		else
			executePythonScriptFile(pyscriptfullpath, FALSE)
	}
	
	void Setup2DArrayFromTagList(object self, number i, string name, number m_wsViewID){
		string fullpath_roi = m_filepath + PSD_TAGFILE_NAME
		
		taggroup tg = newTagGroup()
		if(!(tg.TagGroupLoadFromFile(fullpath_roi))){
			Throw("Unable to find tag list file with specified path")
		}
					
		if(!SISetMode("2D Array"))
			throw("SI mode could not be set")
				
		//Set SI ROI for visual purposes only 
		number t, l, b, r
		roi sROI = SIGetSurveyROI()
		if(!tg.TagGroupGetIndexedTagAsLongRect(i, t, l, b, r)){
			//return FALSE;
			throw("incorrect tag encountered")
		}
		string scan_num = "" + i
		number sizeX, sizeY
		sizeX = r - l
		sizeY = b - t

		// NOTE this has been padded
		sROI.ROISetRectangle( t, l, b , r) //set for visibility purposes
		/*
		result("\n Scan num:" + scan_num)
		result("\n Top:")
		result(t)
		result("\n Bot:")
		result(b)
		result("\n Left:")
		result(l)
		result("\n Right:")
		result(r)
		result("\n Size X:")
		result(sizeX)
		result("\n Size Y:")
		result(sizeY)
		result("\n")
		*/

		// Save the workspace
		number wsID;
		string ext = ".dmw";
		string fullpath = m_SIDataPath;
		fullpath += name;
		fullpath += ext;
		
		// SI Capture
		Acquire2DArray_custom(t/m_surveySizeY, l/m_surveySizeX, b/m_surveySizeY, r/m_surveySizeX, sizeX, sizeY, scan_num)
		result("\n" + dateStamp() + " Acquiring SI");
		
		wsID = WorkspaceGetActive();	//Get ID capture workspaceID
		WorkspaceSetName(wsID ,name);	//Set capture workspaceID name
		workspaceSetActive(wsID);

		// SIWaitForCaptureReadyState();	
		result("\n" + dateStamp() + " Acquisition complete");

		if (DO_QUANTIFICATION){
			// Now we have the SI image, we can do the EELS quantification
			string HL_image_name = "EELS HL SI" // Change as appropriate
			string LL_image_name = "EELS LL SI" // Change as appropriate
			Image HL_data, LL_data, HL_spectrum, LL_spectrum
			FindImageByTitle(HL_image_name, 3, HL_data) // 3 means do not close the image
			FindImageByTitle(LL_image_name, 3, LL_data) // 3 means do not close the image
			// Now do quant
			HL_spectrum := get_EELS_spectrum(HL_data)
			HL_spectrum.showimage()
			setwindowposition(HL_spectrum, 50,600)
			updateimage(HL_spectrum)

			LL_spectrum := get_EELS_spectrum(LL_data)
			LL_spectrum.showimage()
			setwindowposition(LL_spectrum, 450,600)
			updateimage(LL_spectrum)
			// Splicing and quant
			// Now splice the two spectra together using default parameters
			Image spliced_spectrum
			// 0 bad channels, 10 overlap channels - CHANGE THESE AS NEEDED-------------------------------------------------------
			number bad_channels = 0, overlap_channels = 10
			spliced_spectrum := EELS_splice(HL_spectrum, LL_spectrum, bad_channels, overlap_channels)

			number addResultTags = TRUE // Add result tags to the spectrum
			TagGroup quantResults
			quantResults = spliced_spectrum.Quant_Quantify(addResultTags, QUANT_SETUP_NAME)
			// Show the quant results
			quantResults.TagGroupOpenBrowserWindow( 1 )
			spliced_spectrum.showimage()
			setwindowposition(spliced_spectrum, 850,600)
			updateimage(spliced_spectrum)

			// Output the quant results to the console
			TagGroup quant_edges = quantResults.TagGroupGetOrCreateTagList("Edges")
			number edge_tagEntries = quant_edges.TagGroupCountTags()	

			number estim_thickness, inelastic_mfp
			quantResults.TagGroupGetTagAsDouble("Estimated thickness (nm)",estim_thickness)
			quantResults.TagGroupGetTagAsDouble("Inelastic mfp (nm)",inelastic_mfp)
			result("\n Estimated thickness (nm): " + estim_thickness)
			result("\n Inelastic mfp (nm): " + inelastic_mfp)

			TagGroup Edge_results
			for(number k = 0; k < edge_tagEntries; k++){
				quant_edges.TagGroupGetIndexedTagAsTagGroup(k, Edge_results) 
				//Edge_results.TagGroupOpenBrowserWindow(0)
				output_quant_results(Edge_results)
			}
		}

		sleep(3)
		// Save and Close
		workspaceSetActive(wsID)			
		WorkspaceSaveAs(wsID , fullpath);	//save capture workspace
		WorkspaceCloseActive();				//Close SI
		// sleep(m_SI_WaitTime_s);			//wait
		workspaceSetActive(m_wsViewID)		//Set view as active workspace
		result("\n" + dateStamp() + " " + name + " saved");
		
	}
	
	void SI_MultiCapture(object self, string name, number stageIndex_x, number stageIndex_y){
		self.acquireDigiscanImage()	
		self.SurveyIDToTagFile()
		self.py_AnalyseSurveyImage()
		
		string wsName
		
		string fullpath = m_filepath + PSD_TAGFILE_NAME		//tagfile name constant CONSIDER CHANGING THIS 
		taggroup tg = newTagGroup()
		if(!(tg.TagGroupLoadFromFile(fullpath))){
			Throw("Unable to find tag list file with specified path")
		}
		
		number tagEntries = tg.TagGroupCountTags()				
		
		// Quantification requires collation to be off during the loop as it will find images by the titles -  disable it if currently on and then restore after
		string collateWasEnabled = "false"
		if (DO_QUANTIFICATION){
			GetPersistentStringNote(COLLATE_AFTER_ACQ_TAG, collateWasEnabled)
			if (collateWasEnabled == "true"){
				SetPersistentStringNote(COLLATE_AFTER_ACQ_TAG, "false")
			}
		}
		
		for(number k = 0; k < tagEntries; k++){
			wsName = name + "_(" + stageIndex_x + "," + stageIndex_y + ")_" + k;
			self.Setup2DArrayfromTagList(k, wsName, m_wsViewID)
		}
		
		if (DO_QUANTIFICATION && collateWasEnabled == "true"){
			SetPersistentStringNote(COLLATE_AFTER_ACQ_TAG, "true")
		}
	}
	
	//Helper functions
	image OutputCurrentSurveyImage(object self){
		return m_survey
	}
	
	number OutputCurrentSurveyID(object self){
		return m_surveyID
	}
}

void main(){
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// General Params
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	number waitTime_s				= 0			// arbitrary pause to allow data to be saved and stage to settle.
	number stageWait_s				= 10	
	string wsName	

	//User Warning 
	if(!okcanceldialog("EELS Multi SI must be launched from SI technique. Last used SI pixel time and EELS view parameters will be applied. Press ok to continue")){
		throw("user abort")
	}

	//Initialise SIMA Object
    object SIMA 					= alloc(C_SIMultiAutomaton).SIMA_init(waitTime_s,PY_FILENAME)
	SIMA.SetPathAndSerialise()
	

	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// 			DATA ACQUISITION SECTION - Broken up into 3 versions, comment out as wanted
	/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	

	
	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//
	// 			Version 1 - Single area for testing purposes
	//
	/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	

	SIMA.SI_MultiCapture(SI_DATA_PREFIX, 0, 0)
	
	

	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//
	// 			Version 2 - Same Area with in-situ temperature control via DENSsolutions Climate Holder
	//
	/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/*

	// Temp ramps
	number Temp_min, Temp_max, Temp_increment, num_steps, Temp_current
	Temp_min = 160
	Temp_max = 170
	Temp_increment = 5
	num_steps = (Temp_max - Temp_min) / Temp_increment
	
	for (number i = 0; i< num_steps + 1; i++){
		Temp_current = Temp_min + Temp_increment * i
		SetPersistentNumberNote(PERSISTENT_TEMPERATURE_TAG, Temp_current)
		result(Temp_current)
		number j=0
		Climate_SetTemperature(Temp_current)
		sleep(4)

		//Add autofocus routine here

		SIMA.SI_MultiCapture(SI_DATA_PREFIX, Temp_current, j)	
		//sleep(stageWait_s) - optional wait but unnecesary
	}

	*/

	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//
	// 			Version 3 - Multiple areas via serpentine path
	//
	/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/*
	
	//Stage shift applied in serpentine pattern, over M (x axis) by N (y axis) matrix, with step size = stageShift
	number stage_M					= 2;
	number stage_N					= 2;
	number stageShift				= 5;		// On JEOL F200, shift units = microns
	number stageOrigin_x, stageOrigin_y
	EMGetStageXY(stageOrigin_x, stageOrigin_y)
	number stage_x, stage_y

	for(number i = 0; i < stage_M; i++){
		if(i % 2 == 0){
				for(number j = 0; j < stage_N; j++){
					stage_x = stageOrigin_x + (j * stageShift)
					stage_y = stageOrigin_y + (i * stageShift)
					EMSetStageXY(stage_x, stage_y)
					
					//Wait for stage position to be reached
					sleep(stageWait_s)
					
					//Add autofocus here - Example via JEOL here
					JEOL_autofocus(1) // 1 = do autofocus without blocking, 0 = block
					result("\nstage shift:  x: " + i + "\\tstage y: " + j + " begin SIMA")	
					SIMA.SI_MultiCapture(SI_DATA_PREFIX, i, j)	
				}		
		}
		else{
				for(number j = stage_N - 1; j >= 0; j--){
					stage_x = stageOrigin_x + (j * stageShift)
					stage_y = stageOrigin_y + (i * stageShift)
					EMSetStageXY(stage_x, stage_y)
					
					//Wait for stage position to be reached
					sleep(stageWait_s)
					
					//Add autofocus here
					JEOL_autofocus(1) // 1 = do autofocus without blocking, 0 = block
					result("\nstage shift: x: " + i + "\\tstage y: " + j + " begin SIMA")
					SIMA.SI_MultiCapture(SI_DATA_PREFIX, i, j)
				} 
		}
	}

	*/
	// Delete persistent notes at end
	SIMA.SIMA_CleanUp()
} 

main()