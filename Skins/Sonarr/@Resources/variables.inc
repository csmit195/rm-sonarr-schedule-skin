[Variables]
; ------------------------------------------------------------------------
; SONARR CONFIGURATION
; ------------------------------------------------------------------------
; The URL of your Sonarr instance (e.g., http://localhost:8989)
SonarrURL=http://localhost:8989
; Your Sonarr API Key (Found in Sonarr > Settings > General)
SonarrAPIKey=INSERT_API_KEY_HERE

; ------------------------------------------------------------------------
; DISPLAY SETTINGS
; ------------------------------------------------------------------------
; Number of days to show on the skin
MaxDaysToShow=5
; Number of days to fetch from Sonarr (Max 14) (Replace this if you ran a custom gen_meters.js)
MaxGeneratedDays=14
; Whether to show episodes from yesterday (0 = No, 1 = Yes)
ShowYesterday=1
; How often to check for updates (in minutes)
RefreshRate=15

; ------------------------------------------------------------------------
; VISUALS
; ------------------------------------------------------------------------
Width=350
MinHeight=100

; Colors (R,G,B,Alpha)
BgColor=15,18,25,240
HighlightColor=255,255,255,15
ColorTextMain=240,240,240
ColorTextDim=150,150,150
ColorAccentBlue=0,180,255
ColorAccentOrange=255,140,0

; Fonts
HeaderText=Sonarr
FontMain=Segoe UI
FontBold=Segoe UI Semibold
