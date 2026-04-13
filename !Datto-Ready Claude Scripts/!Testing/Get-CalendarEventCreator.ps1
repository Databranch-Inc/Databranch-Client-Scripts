<#
.SYNOPSIS
    Uses the Microsoft Graph API to find a calendar event on a shared mailbox
    and return full event details including organizer, creator, and all metadata.

.DESCRIPTION
    Authenticates to Microsoft Graph using device code flow via direct REST calls
    to login.microsoftonline.com - no dependency on the Graph PowerShell module
    for token management. Queries the shared mailbox calendarView endpoint and
    returns all available event fields.

    No modules required beyond what ships with Windows PowerShell 5.1.

.PARAMETER SharedMailbox
    The UPN or primary SMTP address of the shared mailbox (e.g., vacation@contoso.com).

.PARAMETER EventSubject
    Subject/title of the calendar event to search for. Partial match supported.

.PARAMETER TenantId
    Your Azure AD / Entra tenant ID (GUID or domain, e.g. contoso.onmicrosoft.com).

.PARAMETER StartDateTime
    Filter events scheduled on or after this date. Defaults to 1 year ago.

.PARAMETER EndDateTime
    Filter events scheduled on or before this date. Defaults to 2 years from now.

.PARAMETER ExportPath
    Optional. If specified, exports full results to CSV at this path.

.EXAMPLE
    Get-CalendarEventCreator -SharedMailbox "vacation@contoso.com" -EventSubject "Buck" -TenantId "contoso.onmicrosoft.com"

.NOTES
    Version History:
        v2.0.0.0 - 2026-03-23 - Complete rewrite - removed Microsoft.Graph module dependency entirely
                               - Auth via direct REST device code flow to login.microsoftonline.com
                               - All Graph queries via Invoke-RestMethod with bearer token
                               - No module install required - works with stock PS 5.1
                               - Added -TenantId parameter (required for device code flow)
        v1.2.0.0 - 2026-03-23 - Attempted Invoke-RestMethod + bearer token via Graph module session
        v1.1.0.0 - 2026-03-23 - Rewrote connection block to use device code auth
        v1.0.0.0 - 2026-03-23 - Initial release

    Author:  Databranch / Sam Kirsch
#>

function Get-CalendarEventCreator {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, HelpMessage = "UPN or SMTP of the shared mailbox")]
        [ValidateNotNullOrEmpty()]
        [string]$SharedMailbox,

        [Parameter(Mandatory, HelpMessage = "Subject of the calendar event (partial match)")]
        [ValidateNotNullOrEmpty()]
        [string]$EventSubject,

        [Parameter(Mandatory, HelpMessage = "Tenant ID or domain e.g. contoso.onmicrosoft.com")]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter()]
        [datetime]$StartDateTime = (Get-Date).AddYears(-1),

        [Parameter()]
        [datetime]$EndDateTime = (Get-Date).AddYears(2),

        [Parameter()]
        [string]$ExportPath
    )

    #region --- Version Info ---
    $ScriptVersion = "2.0.0.0"
    $ScriptName    = "Get-CalendarEventCreator"
    # Microsoft's well-known public client ID for PowerShell / Azure CLI delegated access
    $ClientId      = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
    $Scope         = "https://graph.microsoft.com/Calendars.Read offline_access"
    #endregion

    #region --- Banner ---
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $ScriptName  v$ScriptVersion" -ForegroundColor Cyan
    Write-Host "  Calendar Event Lookup via Graph API" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Mailbox  : $SharedMailbox"
    Write-Host "  Tenant   : $TenantId"
    Write-Host "  Subject  : $EventSubject"
    Write-Host "  Range    : $($StartDateTime.ToString('yyyy-MM-dd')) -> $($EndDateTime.ToString('yyyy-MM-dd'))"
    Write-Host ""
    #endregion

    #region --- Device Code Auth ---
    Write-Host "  [~] Requesting device code..." -ForegroundColor Yellow

    $deviceCodeUri  = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"
    $tokenUri       = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    try {
        $deviceCodeResponse = Invoke-RestMethod -Uri $deviceCodeUri -Method POST -Body @{
            client_id = $ClientId
            scope     = $Scope
        } -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to request device code: $_"
        return
    }

    Write-Host ""
    Write-Host "  *** ACTION REQUIRED ***" -ForegroundColor Yellow
    Write-Host "  $($deviceCodeResponse.message)" -ForegroundColor White
    Write-Host ""

    # Poll for token
    Write-Host "  [~] Waiting for authentication..." -ForegroundColor Yellow
    $interval   = $deviceCodeResponse.interval
    $expiry     = (Get-Date).AddSeconds($deviceCodeResponse.expires_in)
    $accessToken = $null

    while ((Get-Date) -lt $expiry) {
        Start-Sleep -Seconds $interval

        try {
            $tokenResponse = Invoke-RestMethod -Uri $tokenUri -Method POST -Body @{
                grant_type   = "urn:ietf:params:oauth:grant-type:device_code"
                client_id    = $ClientId
                device_code  = $deviceCodeResponse.device_code
            } -ErrorAction Stop

            $accessToken = $tokenResponse.access_token
            Write-Host "  [+] Authenticated successfully." -ForegroundColor Green
            break
        }
        catch {
            $errBody = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($errBody -and $errBody.error -eq "authorization_pending") {
                Write-Host "      Waiting..." -ForegroundColor DarkGray
                continue
            }
            elseif ($errBody -and $errBody.error -eq "slow_down") {
                $interval += 5
                continue
            }
            else {
                Write-Error "Authentication failed: $($_.ErrorDetails.Message)"
                return
            }
        }
    }

    if (-not $accessToken) {
        Write-Error "Authentication timed out. Please re-run the script."
        return
    }
    #endregion

    #region --- Build Headers and URI ---
    $headers = @{
        Authorization = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    $startStr       = $StartDateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $endStr         = $EndDateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $mailboxEncoded = [Uri]::EscapeDataString($SharedMailbox)
    $baseUri        = "https://graph.microsoft.com/v1.0/users/$mailboxEncoded/calendarView"

    $selectFields = @(
        "id", "subject", "organizer", "attendees",
        "start", "end", "createdDateTime", "lastModifiedDateTime",
        "bodyPreview", "location", "isAllDay", "isCancelled",
        "isOrganizer", "recurrence", "sensitivity", "showAs",
        "importance", "categories", "webLink"
    ) -join ","

    $uri = "${baseUri}?startDateTime=${startStr}&endDateTime=${endStr}&`$select=${selectFields}&`$top=100"
    #endregion

    #region --- Query Graph (paginated) ---
    Write-Host "  [~] Querying Graph calendar for '$SharedMailbox'..." -ForegroundColor Yellow

    $allEvents = [System.Collections.Generic.List[object]]::new()
    $nextUri   = $uri
    $page      = 1

    do {
        try {
            $response = Invoke-RestMethod -Uri $nextUri -Method GET -Headers $headers -ErrorAction Stop
            $events   = $response.value

            if ($events) {
                $allEvents.AddRange($events)
                Write-Host "      [Page $page] Retrieved $($events.Count) events..." -ForegroundColor DarkGray
                $page++
            }

            $nextUri = $response.'@odata.nextLink'
        }
        catch {
            Write-Host "  [!] Graph request failed:" -ForegroundColor Red
            Write-Host "      $($_.Exception.Message)" -ForegroundColor Red
            if ($_.ErrorDetails.Message) {
                $errDetail = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($errDetail) {
                    Write-Host "      Code   : $($errDetail.error.code)" -ForegroundColor Red
                    Write-Host "      Message: $($errDetail.error.message)" -ForegroundColor Red
                }
            }
            return
        }
    } while ($nextUri)

    Write-Host "  [+] Total events retrieved: $($allEvents.Count)" -ForegroundColor Green
    #endregion

    #region --- Filter by Subject ---
    Write-Host "  [~] Filtering for subject matching '$EventSubject'..." -ForegroundColor Yellow

    $matchedEvents = $allEvents | Where-Object { $_.subject -like "*$EventSubject*" }

    if (-not $matchedEvents -or @($matchedEvents).Count -eq 0) {
        Write-Host ""
        Write-Host "  [!] No events found matching '$EventSubject'." -ForegroundColor Yellow
        Write-Host "      Suggestions:" -ForegroundColor DarkGray
        Write-Host "        - Try a shorter keyword" -ForegroundColor DarkGray
        Write-Host "        - Widen StartDateTime / EndDateTime (filters by scheduled event date)" -ForegroundColor DarkGray
        Write-Host "        - Confirm the shared mailbox UPN is correct" -ForegroundColor DarkGray
        Write-Host "        - Verify Calendars.Read permission on this mailbox" -ForegroundColor DarkGray
        Write-Host ""
        return
    }
    #endregion

    #region --- Output Results ---
    Write-Host ""
    Write-Host "  [+] Found $(@($matchedEvents).Count) matching event(s):" -ForegroundColor Green
    Write-Host ""

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($event in $matchedEvents) {

        $organizerName  = if ($event.organizer -and $event.organizer.emailAddress) { $event.organizer.emailAddress.name }    else { "N/A" }
        $organizerEmail = if ($event.organizer -and $event.organizer.emailAddress) { $event.organizer.emailAddress.address } else { "N/A" }
        $startTime      = if ($event.start)    { "$($event.start.dateTime) ($($event.start.timeZone))" } else { "N/A" }
        $endTime        = if ($event.end)      { "$($event.end.dateTime) ($($event.end.timeZone))" }     else { "N/A" }
        $location       = if ($event.location) { $event.location.displayName }                          else { "N/A" }

        $attendeeList = if ($event.attendees -and $event.attendees.Count -gt 0) {
            ($event.attendees | ForEach-Object {
                "$($_.emailAddress.name) ($($_.emailAddress.address)) [$($_.type)]"
            }) -join "; "
        }
        else { "None" }

        $result = [PSCustomObject]@{
            Subject              = $event.subject
            OrganizerName        = $organizerName
            OrganizerEmail       = $organizerEmail
            EventStart           = $startTime
            EventEnd             = $endTime
            IsAllDay             = $event.isAllDay
            IsCancelled          = $event.isCancelled
            IsOrganizer          = $event.isOrganizer
            CreatedDateTime      = $event.createdDateTime
            LastModifiedDateTime = $event.lastModifiedDateTime
            Location             = $location
            Attendees            = $attendeeList
            BodyPreview          = $event.bodyPreview
            Sensitivity          = $event.sensitivity
            ShowAs               = $event.showAs
            Importance           = $event.importance
            Categories           = ($event.categories -join ", ")
            IsRecurring          = ($null -ne $event.recurrence)
            WebLink              = $event.webLink
            GraphEventId         = $event.id
        }

        $results.Add($result)

        Write-Host "  -------------------------------------" -ForegroundColor DarkGray
        Write-Host "  Subject      : $($result.Subject)" -ForegroundColor White
        Write-Host "  Organizer    : $organizerName ($organizerEmail)" -ForegroundColor Green
        Write-Host "  Created      : $($result.CreatedDateTime)"
        Write-Host "  Last Modified: $($result.LastModifiedDateTime)"
        Write-Host "  Event Start  : $startTime"
        Write-Host "  Event End    : $endTime"
        Write-Host "  All Day      : $($result.IsAllDay)"
        Write-Host "  Location     : $location"
        Write-Host "  Attendees    : $attendeeList"
        Write-Host "  Body Preview : $($result.BodyPreview)"
        Write-Host "  Recurring    : $($result.IsRecurring)"
        Write-Host ""
    }

    if ($ExportPath) {
        try {
            $results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
            Write-Host "  [+] Exported to: $ExportPath" -ForegroundColor Green
        }
        catch {
            Write-Warning "Export failed: $_"
        }
    }

    Write-Host "  -------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [+] Done." -ForegroundColor Cyan
    Write-Host ""
    #endregion

    return $results
}
