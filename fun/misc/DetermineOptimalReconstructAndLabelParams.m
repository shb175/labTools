%% Determine the Optimal Reconstruct & Label Pipeline Parameters
% author: NWB (with assistance from ChatGPT)
% date (created): 18 May 2025
% purpose: to iterate through various Vicon Nexus 'Reconstruct & Label'
% pipeline parameters to determine the optimal configuration based on
% metrics such as the percentage of frames missing, the average number of
% gaps per marker, and the maximum and median gap length.

% TODO:
%   1. Loop through exemplar trials from all SML Lab studies or study types
%   2. Save RGT, LGT, RANK, LANK marker trajectories in MAT file for later
%       analysis just in case
%   3. Generate and save trajectory figures for GT and ANK markers

%% 1) Define Paths
pathData   = 'Z:\Nathan\ViconNexusReconstructAndLabel\Vicon\';
pathOutCSV = ['Z:\Nathan\ViconNexusReconstructAndLabel\' ...
    'Results_C3S_S1_OGPost_2.csv'];

% get all sessions in data directory not including current and parent
dirsSess = dir(pathData);
dirsSess = dirsSess([dirsSess.isdir] & ...
    ~ismember({dirsSess.name},{'.','..'}));
numSess = numel(dirsSess);                  % number of sessions to process
if numSess == 0                             % if no session folders, ...
    error('No session folders found in %s',pathData);
end

%% 2) Initialize Vicon Nexus SDK & Prepare the Results Container Structure
vicon = ViconNexus();   % assumes ViconNexus() is on the MATLAB path

% preallocate a struct array to hold per-trial results:
%   • ParticipantName, TrialID, Use3DPredictions,
%     EnvironmentalDriftTolerance, MinCamerasToStartTraj,
%     MinCamerasToContTraj, MinSeparation, PercentMissing_All,
%     NumGapsPerMarker_All, MaxGapLength_All, MedianGapLength_All,
%     PercentMissing_Subset, NumGapsPerMarker_Subset, MaxGapLength_Subset,
%     MedianGapLength_Subset
results = struct( ...
    'ParticipantName',              {}, ...
    'TrialID',                      {}, ...
    'Use3DPredictions',             {}, ...
    'EnvironmentalDriftTolerance',	{}, ...
    'MinCamerasToStartTraj',        {}, ...
    'MinCamerasToContTraj',         {}, ...
    'MinSeparation',                {}, ...
    'PercentMissing_All',           {}, ...
    'NumGapsPerMarker_All',         {}, ...
    'MaxGapLength_All',             {}, ...
    'MedianGapLength_All',          {}, ...
    'PercentMissing_Subset',        {}, ...
    'NumGapsPerMarker_Subset',      {}, ...
    'MaxGapLength_Subset',          {}, ...
    'MedianGapLength_Subset',       {} ...
    );

%% 3) Locate & Read the 'Reconstruct And Label Test.Pipeline' File
pathPipeline = ['C:\Users\Public\Documents\Vicon\Nexus2.x\' ...
    'Configurations\Pipelines\Reconstruct And Label Test.Pipeline'];

% read in all lines once and search for the pertinent parameter lines
params = readlines(pathPipeline);

% find exactly one line index for each parameter
ind3DPredict = find(contains(params,'Reconstructor.3DPredictions'));
indEnvDriftTol = find(contains(params,'EnvironmentalDriftTolerance'));
indMinCamsToStartTraj = find(contains(params,'"MinCams"'));
indMinCamsToContTraj = find(contains(params,'MinCamsWithPrediction'));
indMinSeparation = find(contains(params,'MinSeparation'));

% sanity check
if any([numel(ind3DPredict) numel(indEnvDriftTol) ...
        numel(indMinCamsToStartTraj) numel(indMinCamsToContTraj) ...
        numel(indMinSeparation)] ~= 1)
    error(['Each pipeline parameter must appear exactly once in the ' ...
        'XML file.']);
end

%% 4) Define the Subset of Critical Markers to Compute Separately
markersSubset = {'RGT','LGT','RANK','LANK'};

%% 5) Specify Set of Reconstruct & Label Parameters to Loop Through
predict3D = [true false];                   % should use 3D predictions
envDriftTol = 2.00:0.50:4.50;               % environmental drift tolerance
minCamsToStartTraj = 2:3;                   % minimum cameras to start
minCamsToContTraj = 2;                      % minimum cameras to continue
minSeparation = 14:5:34;                    % minimum marker separation
% minCentroidRadius = 0; % 0:2:4;
% maxCentroidRadius = 50; % 30:10:50;
% create set of parameter combinations
paramSets = allcomb(predict3D,envDriftTol,minCamsToStartTraj, ...
    minCamsToContTraj,minSeparation);
numParamSets = size(paramSets,1);           % number of parameter sets

%% 6) Loop Over All Parameters Sets & Trials & Compute Outcome Measures
for set = 1:numParamSets                    % for each parameter set, ...
    % 6a) overwrite the pertinent parameters lines in the pipeline XML file
    fprintf(['---\nAssessing the following parameter set:\n' ...
        '  • 3D Predictions = %u;\n' ...
        '  • Environmental Drift Tolerance = %03.1f;\n' ...
        '  • Minimum Cameras to Start Trajectory = %u;\n' ...
        '  • Minimum Cameras to Continue Trajectory = %u;\n' ...
        '  • Minimum Reconstruction Separation = %u...\n'], ...
        paramSets(set,1),paramSets(set,2),paramSets(set,3), ...
        paramSets(set,4),paramSets(set,5));
    shouldPredict3D = paramSets(set,1);     % should use 3D predictions?
    if shouldPredict3D                      % if 3D predictions is on, ...
        params(ind3DPredict) = ['      ' ...  enable it in pipeline file
            '<Param name="Reconstructor.3DPredictions" value="true"/>'];
    else                                    % otherwise, ...
        params(ind3DPredict) = ['      ' ...  disable it in pipeline file
            '<Param name="Reconstructor.3DPredictions" value="false"/>'];
    end
    params(indEnvDriftTol) = sprintf(['      <Param name="' ...
        'EnvironmentalDriftTolerance" value="%03.1f"/>'],paramSets(set,2));
    params(indMinCamsToStartTraj) = sprintf(['      <Param name="' ...
        'MinCams" value="%u"/>'],paramSets(set,3));
    params(indMinCamsToContTraj) = sprintf(['      <Param name="' ...
        'MinCamsWithPrediction" value="%u"/>'],paramSets(set,4));
    params(indMinSeparation) = sprintf(['      <Param name="' ...
        'MinSeparation" value="%u"/>'],paramSets(set,5));

    % 6b) overwrite ALL 209 lines back into the pipeline XML file
    % if MATLAB R2022a or later, use 'writelines(params,pipelineFile);'
    fidW = fopen(pathPipeline,'w');         % open the file to overwrite
    if fidW < 0                             % if file did not open, ...
        error('Could not open pipeline file for writing: %s',pathPipeline);
    end
    for line = 1:numel(params)              % for each line in file, ...
        fprintf(fidW,'%s\n',params(line));  % overwrite it
    end
    fclose(fidW);                           % close file
    fprintf(['Successfully updated parameters in ''Reconstruct And ' ...
        'Label Test'' pipeline XML file.\n\n']);

    % 6i) compute aggregate measures over ALL sessions and trials
    PercentMissing_All_ParamSet = nan(numSess,1);
    NumGapsPerMarker_All_ParamSet = nan(numSess,1);
    MaxGapLength_All_ParamSet = nan(numSess,1);
    MedianGapLength_All_ParamSet = nan(numSess,1);
    PercentMissing_Subset_ParamSet = nan(numSess,1);
    NumGapsPerMarker_Subset_ParamSet = nan(numSess,1);
    MaxGapLength_Subset_ParamSet = nan(numSess,1);
    MedianGapLength_Subset_ParamSet = nan(numSess,1);

    for sess = 1:numel(dirsSess)            % for each session, ...
        nameSess = dirsSess(sess).name;
        pathSess = fullfile(pathData,nameSess);
        fprintf('Processing %s\n',nameSess);

        % get all trial files that start with 'Trial' and end in '.x1d'
        trialFiles = dir(fullfile(pathSess,'Trial*.x1d'));
        if isempty(trialFiles)              % if no trial files found, ...
            error('No trials found in session folder: %s\n',pathSess);
        end

        % extract trial indices from filenames (assumes 'TrialXX.x1d')
        [~,namesFiles] = cellfun(@fileparts,{trialFiles.name}, ...
            'UniformOutput',false);
        indsTrials = cellfun(@(s) str2double(s(end-1:end)),namesFiles);

        for tr = 1:numel(indsTrials)        % for each trial specified, ...
            trialID = indsTrials(tr);       % retrieve trial number
            trialName = sprintf('Trial%02d',trialID);
            pathTrial = fullfile(pathSess,trialName);
            fprintf('Processing %s\n',trialName);

            % 6c) open the trial in Nexus (if not already open)
            if ~dataMotion.openTrialIfNeeded(pathTrial,vicon)
                warning('  • Could not open %s. Skipping.\n',trialName);
                continue;                   % skip trial if could not open
            end

            % 6d) run the "Reconstruct And Label Test" pipeline
            try                             % try running pipeline
                vicon.RunPipeline('Reconstruct And Label Test','',200);
            catch ME
                warning(ME.identifier, ...
                    '  • Nexus.RunPipeline failed: %s\n',ME.message);
                continue;
            end

            % 6e) get participant name (assuming only one per trial)
            subject = vicon.GetSubjectNames();
            if isempty(subject)
                warning('  • No subject found in %s. Skipping.\n', ...
                    trialName);
                continue;
            end
            subject = subject{1};

            % 6f) retrieve all marker names for this subject
            markersAll = vicon.GetMarkerNames(subject);
            numMarkers = numel(markersAll);
            if numMarkers == 0
                warning(['  • No markers found for participant %s. ' ...
                    'Skipping.\n'],subject);
                continue;
            end

            % 6g) preallocate temporary arrays to store per-marker metrics
            percentMissing = nan(numMarkers,1);	% percentage frames missing
            numGaps = nan(numMarkers,1);        % number of gap events
            gapLengths = nan(numMarkers,1000);  % largest gap length
            isInSubset = false(numMarkers,1);   % is marker in subset?

            % 6h) retrieve marker trajectory, compute missing frames & gaps
            for mrkr = 1:numMarkers             % for each marker, ...
                nameMarker = markersAll{mrkr};  % name of current marker
                isInSubset(mrkr) = any(strcmp(nameMarker,markersSubset));

                try                             % try to get marker traj.
                    [~,~,~,existsTraj] = ...
                        vicon.GetTrajectory(subject,nameMarker);
                    % existsTraj is logical vector: true  = visible,
                    %                               false = occluded (miss)
                catch
                    warning(['    • Could not retrieve trajectory for ' ...
                        '%s. Treating as fully missing.\n'],nameMarker);
                    existsTraj = false(vicon.GetFrameCount(),1);
                end

                totalFrames = numel(existsTraj);% total number of frames
                numMissing = sum(~existsTraj);  % number of missing frames
                percentMissing(mrkr) = (numMissing / totalFrames) * 100;

                dv = diff([0; (~existsTraj)'; 0]);  % find marker gaps
                runBoundaries = find(dv~=0);        % changes
                % present & gap run lengths
                runLengths = diff(runBoundaries);
                % +1 = gap starts, -1 = ends
                runValues = dv(runBoundaries);
                gapRuns = runLengths(runValues==1);
                numGaps(mrkr) = numel(gapRuns);     % number of marker gaps
                gapLengths(mrkr,1:numGaps(mrkr)) = gapRuns';
            end

            % 6i) compute aggregate measures over ALL markers
            PercentMissing_All = mean(percentMissing);
            NumGapsPerMarker_All = sum(numGaps) / numMarkers;
            MaxGapLength_All = max(gapLengths,[],'all');
            MedianGapLength_All = median(gapLengths,'all','omitnan');

            % 6j) compute aggregate measures over SUBSET markers
            indsMarkersSubset = find(isInSubset);
            if isempty(indsMarkersSubset)       % if no subset markers, ...
                PercentMissing_Subset = NaN;    % set all values to 'NaN'
                NumGapsPerMarker_Subset = NaN;
                MaxGapLength_Subset = NaN;
                MedianGapLength_Subset = NaN;
            else                                % otherwise, ...
                PercentMissing_Subset = ...
                    mean(percentMissing(indsMarkersSubset));
                NumGapsPerMarker_Subset = ...
                    sum(numGaps(indsMarkersSubset)) / ...
                    numel(indsMarkersSubset);
                MaxGapLength_Subset = ...
                    max(gapLengths(indsMarkersSubset),[],'all');
                MedianGapLength_Subset = ...
                    median(gapLengths(indsMarkersSubset),'all','omitnan');
            end

            % 6k) append a single row to the 'results' structure
            results(end+1) = struct( ...
                'ParticipantName',              subject, ...
                'TrialID',                      trialID, ...
                'Use3DPredictions',            	shouldPredict3D, ...
                'EnvironmentalDriftTolerance',	paramSets(set,2), ...
                'MinCamerasToStartTraj',        paramSets(set,3), ...
                'MinCamerasToContTraj',         paramSets(set,4), ...
                'MinSeparation',                paramSets(set,5), ...
                'PercentMissing_All',           PercentMissing_All, ...
                'NumGapsPerMarker_All',         NumGapsPerMarker_All, ...
                'MaxGapLength_All',             MaxGapLength_All, ...
                'MedianGapLength_All',          MedianGapLength_All, ...
                'PercentMissing_Subset',        PercentMissing_Subset, ...
                'NumGapsPerMarker_Subset',      NumGapsPerMarker_Subset,...
                'MaxGapLength_Subset',          MaxGapLength_Subset, ...
                'MedianGapLength_Subset',       MedianGapLength_Subset ...
                );

            % TODO: update to handle case of multiple trials per session
            PercentMissing_All_ParamSet(sess) = PercentMissing_All;
            NumGapsPerMarker_All_ParamSet(sess) = NumGapsPerMarker_All;
            MaxGapLength_All_ParamSet(sess) = MaxGapLength_All;
            MedianGapLength_All_ParamSet(sess) = MedianGapLength_All;
            PercentMissing_Subset_ParamSet(sess) = PercentMissing_Subset;
            NumGapsPerMarker_Subset_ParamSet(sess) = NumGapsPerMarker_Subset;
            MaxGapLength_Subset_ParamSet(sess) = MaxGapLength_Subset;
            MedianGapLength_Subset_ParamSet(sess) = MedianGapLength_Subset;

            fprintf(['    • PercentMissing_All=%.2f%%, Gaps/Marker_All=' ...
                '%.2f, MaxGap_All=%u frames, MedianGap_All=%.2f frames\n'], ...
                PercentMissing_All,NumGapsPerMarker_All, ...
                MaxGapLength_All,MedianGapLength_All);
            fprintf(['      Subset → PercentMissing=%.2f%%, Gaps/Marker=' ...
                '%.2f, MaxGap=%u frames, MedianGap=%.2f frames\n\n'], ...
                PercentMissing_Subset,NumGapsPerMarker_Subset, ...
                MaxGapLength_Subset,MedianGapLength_Subset);
        end
    end

    % 6l) compute averages across trials for parameter set
    results(end+1) = struct( ...
        'ParticipantName',              'NA', ...
        'TrialID',                      NaN, ...
        'Use3DPredictions',            	shouldPredict3D, ...
        'EnvironmentalDriftTolerance',	paramSets(set,2), ...
        'MinCamerasToStartTraj',        paramSets(set,3), ...
        'MinCamerasToContTraj',         paramSets(set,4), ...
        'MinSeparation',                paramSets(set,5), ...
        'PercentMissing_All',           mean(PercentMissing_All_ParamSet), ...
        'NumGapsPerMarker_All',         mean(NumGapsPerMarker_All_ParamSet), ...
        'MaxGapLength_All',             mean(MaxGapLength_All_ParamSet), ...
        'MedianGapLength_All',          mean(MedianGapLength_All_ParamSet), ...
        'PercentMissing_Subset',        mean(PercentMissing_Subset_ParamSet), ...
        'NumGapsPerMarker_Subset',      mean(NumGapsPerMarker_Subset_ParamSet), ...
        'MaxGapLength_Subset',          mean(MaxGapLength_Subset_ParamSet), ...
        'MedianGapLength_Subset',       mean(MedianGapLength_Subset_ParamSet) ...
        );

    fprintf(['Parameter Set Means Across All Trials:\n' ...
        '    • PercentMissing_All=%.2f%%, Gaps/Marker_All=' ...
        '%.2f, MaxGap_All=%.2f frames, MedianGap_All=%.2f frames\n'], ...
        mean(PercentMissing_All_ParamSet), ...
        mean(NumGapsPerMarker_All_ParamSet), ...
        mean(MaxGapLength_All_ParamSet), ...
        mean(MedianGapLength_All_ParamSet));
    fprintf(['    Subset → PercentMissing=%.2f%%, Gaps/Marker=' ...
        '%.2f, MaxGap=%.2f frames, MedianGap=%.2f frames\n'], ...
        mean(PercentMissing_Subset_ParamSet), ...
        mean(NumGapsPerMarker_Subset_ParamSet), ...
        mean(MaxGapLength_Subset_ParamSet), ...
        mean(MedianGapLength_Subset_ParamSet));
end

%% 7) Save Summary Results to a CSV File
T = struct2table(results);
writetable(T,pathOutCSV);
fprintf('\nSummary written to:\n   %s\n',pathOutCSV);

