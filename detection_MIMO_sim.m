% =========================================================================
% -- Data Detection in Massive MU-MIMO Simulator
% -------------------------------------------------------------------------
% -- (c) 2020 Christoph Studer and Oscar Castañeda
% -- e-mail: studer@ethz.ch and caoscar@ethz.ch
% -------------------------------------------------------------------------
% -- If you use this simulator or parts of it, then you must cite our 
% -- paper: 
% -- Oscar Castañeda, Tom Goldstein, and Christoph Studer,
% -- "Data Detection in Large Multi-Antenna Wireless Systems via
% -- Approximate Semidefinite Relaxation," 
% -- IEEE Transactions on Circuits and Systems I: Regular Papers,
% -- vol. 63, no. 12, pp. 2334-2346, Dec. 2016.
% =========================================================================

function detection_MIMO_sim(varargin)

  % -- set up default/custom parameters
  
  if isempty(varargin)
    
    disp('using default simulation settings and parameters...')
        
    % set default simulation parameters     
    par.runId = 0;         % simulation ID (used to reproduce results)
    par.MR = 32;           % receive antennas 
    par.MT = 16;           % transmit antennas (set not larger than MR!)         
    par.mod = 'QPSK';      % modulation type: 'BPSK','QPSK','16QAM','64QAM'             
    par.trials = 1e4;      % number of Monte-Carlo trials (transmissions)
    par.simName = ...      % simulation name (used for saving results)
      ['ERR_', num2str(par.MR), 'x', num2str(par.MT), '_', ...
        par.mod, '_', num2str(par.trials),'Trials'];
    par.SNRdB_list = ...   % list of SNR [dB] values to be simulated        
      0:2:12;
    par.los = 0;           % use line-of-sight (LoS) channel model
    par.detector = ...     % define detector(s) to be simulated. Options:
     {'SIMO','MMSE',...    % 'SIMO', 'ML', 'MRC', 'ZF', 'MMSE', 'SDR',
      'TASER','ADMIN',...  % 'TASER', 'RBR', 'ADMIN', 'BOX', 'OCD_MMSE',
      'OCD_BOX','KBEST'};  % 'OCD_BOX', 'KBEST'
                           % NOTE: 'ML' and 'SDR' take a long time if used
                           %       for large systems 
                           % NOTE: 'SDR' requires CVX, available here:
                           %       http://cvxr.com/cvx/download/                         
                                                  
    % TASER parameters ----------------------------------------------------
    par.TASER.iters = 100;       % Number of TASER iterations
    par.TASER.alphaScale = 0.99; % Alpha scale for TASER's step size.
    %Step size used for different systems and iid Rayleigh:
    %-------------------------------------------------------------
    % MR / MT | Example system | Modulation | par.TASER.alphaScale
    % ratio   | (MRxMT)        | scheme     |
    %-------------------------------------------------------------
    % 1       | 32x32          | BPSK       | 0.99
    % 2       | 64x32          | BPSK       | 0.95
    % 4       | 128x32         | BPSK       | 0.8
    % 8       | 256x32         | BPSK       | 0.75
    % 1       | 32x32          | QPSK       | 0.99
    % 2       | 64x32          | QPSK       | 0.99
    % 4       | 128x32         | QPSK       | 0.99
    % 8       | 256x32         | QPSK       | 0.85
    %-------------------------------------------------------------
    %For LoS channels, you will need to tune par.TASER.alphaScale
    %For 32x16 LoS QPSK, 0.85 worked well
    
    % RBR parameters ------------------------------------------------------
    par.RBR.iters = 20;       % Number of RBR iterations
    
    % ADMIN parameters ----------------------------------------------------
    par.ADMIN.betaScale = 3;  % =1 returns biased MMSE on first iteration,
                              % but tuning may improve performance
    par.ADMIN.iters = 5;      % Number of ADMIN iterations                           
    par.ADMIN.gamma = 2;      % Step size (>0) for Lagrangian vector update
                              % A value <1 ensures convergence of ADMM, but
                              % larger values may improve performance
                              
    % BOX parameters ----------------------------------------------------
    par.BOX.iters = 10;       % Number of BOX iterations
    par.BOX.tau = 2^-7;       % Step size (>0) for gradient descent

    % OCD MMSE parameters -------------------------------------------------
    par.OCD_MMSE.iters = 10;   % Number of OCD_MMSE iterations      
    
    % OCD BOX parameters -------------------------------------------------
    par.OCD_BOX.iters = 10;    % Number of OCD_BOX iterations
    
    % K-BEST parameters ---------------------------------------------------
    par.KBEST.K = 5;          % Number of best nodes to consider at a time
    
  else
      
    disp('use custom simulation settings and parameters...')    
    par = varargin{1};     % only argument is par structure
    
  end

  % -- initialization
  
  % use runId random seed (enables reproducibility)
  rng(par.runId,'twister'); 

  % set up Gray-mapped constellation alphabet (according to IEEE 802.11)
  switch (par.mod)
    case 'BPSK'
      par.symbols = [ -1 1 ];
    case 'QPSK' 
      par.symbols = [ -1-1i,-1+1i, ...
                      +1-1i,+1+1i ];
    case '16QAM'
      par.symbols = [ -3-3i,-3-1i,-3+3i,-3+1i, ...
                      -1-3i,-1-1i,-1+3i,-1+1i, ...
                      +3-3i,+3-1i,+3+3i,+3+1i, ...
                      +1-3i,+1-1i,+1+3i,+1+1i ];
    case '64QAM'
      par.symbols = [ -7-7i,-7-5i,-7-1i,-7-3i,-7+7i,-7+5i,-7+1i,-7+3i, ...
                      -5-7i,-5-5i,-5-1i,-5-3i,-5+7i,-5+5i,-5+1i,-5+3i, ...
                      -1-7i,-1-5i,-1-1i,-1-3i,-1+7i,-1+5i,-1+1i,-1+3i, ...
                      -3-7i,-3-5i,-3-1i,-3-3i,-3+7i,-3+5i,-3+1i,-3+3i, ...
                      +7-7i,+7-5i,+7-1i,+7-3i,+7+7i,+7+5i,+7+1i,+7+3i, ...
                      +5-7i,+5-5i,+5-1i,+5-3i,+5+7i,+5+5i,+5+1i,+5+3i, ...
                      +1-7i,+1-5i,+1-1i,+1-3i,+1+7i,+1+5i,+1+1i,+1+3i, ...
                      +3-7i,+3-5i,+3-1i,+3-3i,+3+7i,+3+5i,+3+1i,+3+3i ];
                         
  end

  % extract average symbol energy
  par.Es = mean(abs(par.symbols).^2); 
  
  % precompute bit labels
  par.Q = log2(length(par.symbols)); % number of bits per symbol
  par.bits = de2bi(0:length(par.symbols)-1,par.Q,'left-msb');

  % track simulation time
  time_elapsed = 0;
  
  % -- start simulation 
  
  % initialize result arrays (detector x SNR)
  % vector error rate:
  res.VER = zeros(length(par.detector),length(par.SNRdB_list)); 
  % symbol error rate:
  res.SER = zeros(length(par.detector),length(par.SNRdB_list));
  % bit error rate:
  res.BER = zeros(length(par.detector),length(par.SNRdB_list));

  % generate random bit stream (antenna x bit x trial)
  bits = randi([0 1],par.MT,par.Q,par.trials);

  % trials loop
  tic
  for t=1:par.trials
  
    % generate transmit symbol
    idx = bi2de(bits(:,:,t),'left-msb')+1;
    s = par.symbols(idx).';
  
    % generate iid Gaussian channel matrix & noise vector
    n = sqrt(0.5)*(randn(par.MR,1)+1i*randn(par.MR,1));
    if par.los
      H = los(par); % we will use the planar wave model
    else
      H = sqrt(0.5)*(randn(par.MR,par.MT)+1i*randn(par.MR,par.MT));
    end
    
    % transmit over noiseless channel (will be used later)
    x = H*s;
  
    % SNR loop
    for k=1:length(par.SNRdB_list)
      
      % compute noise variance 
      % (average SNR per receive antenna is: SNR=MT*Es/N0)
      N0 = par.MT*par.Es*10^(-par.SNRdB_list(k)/10);
      
      % transmit data over noisy channel
      y = x+sqrt(N0)*n;
    
      % algorithm loop      
      for d=1:length(par.detector)

        switch (par.detector{d})     % select algorithms
          case 'SIMO'                % SIMO lower bound detector
            [idxhat,bithat] = SIMO(par,H,y,s);
          case 'ML'                  % ML detection using sphere decoding
            [idxhat,bithat] = ML(par,H,y);
          case 'MRC'                 % unbiased MRC detection
            [idxhat,bithat] = MRC(par,H,y);
          case 'ZF'                  % unbiased ZF detection
            [idxhat,bithat] = ZF(par,H,y);
          case 'MMSE'                % unbiased MMSE detector
            [idxhat,bithat] = MMSE(par,H,y,N0);
          case 'SDR'                 % Detection via exact SDR
            [idxhat,bithat] = SDR(par,H,y);         
          case 'TASER'               % TASER detector
            [idxhat,bithat] = TASER(par,H,y);
          case 'RBR'               % RBR detector
            [idxhat,bithat] = RBR(par,H,y);            
          case 'ADMIN'               % ADMIN detector
            [idxhat,bithat] = ADMIN(par,H,y,N0);
          case 'BOX'                 % BOX detector
            [idxhat,bithat] = BOX(par,H,y);
          case 'OCD_MMSE'            % OCD MMSE detector
            [idxhat,bithat] = OCD_MMSE(par,H,y,N0);
          case 'OCD_BOX'             % OCD BOX detector
            [idxhat,bithat] = OCD_BOX(par,H,y);            
          case 'KBEST'               % K-Best detector
            [idxhat,bithat] = KBEST(par,H,y);
          otherwise
            error('par.detector type not defined.')      
        end

        % -- compute error metrics
        err = (idx~=idxhat);
        res.VER(d,k) = res.VER(d,k) + any(err);
        res.SER(d,k) = res.SER(d,k) + sum(err)/par.MT;    
        res.BER(d,k) = res.BER(d,k) + ...
                         sum(sum(bits(:,:,t)~=bithat))/(par.MT*par.Q);                   
        
      end % algorithm loop
                 
    end % SNR loop    
    
    % keep track of simulation time    
    if toc>10
      time = toc;
      time_elapsed = time_elapsed + time;
      fprintf('estimated remaining simulation time: %3.0f min.\n', ...
                time_elapsed*(par.trials/t-1)/60);
      tic
    end      
  
  end % trials loop
  
  % normalize results
  res.VER = res.VER/par.trials;
  res.SER = res.SER/par.trials;
  res.BER = res.BER/par.trials;
  res.time_elapsed = time_elapsed;
  
  % -- save final results (par and res structures)

  save([ par.simName '_' num2str(par.runId) ],'par','res');
  
  % -- show results (generates fairly nice Matlab plot) 
      
  marker_style = {'bo-','rs--','mv-.','kp:','g*-','c>--','yx:'};
  figure(1)
  for d = 1:length(par.detector)
    if d==1
      semilogy(par.SNRdB_list,res.VER(d,:),marker_style{d},'LineWidth',2)
      hold on
    else
      semilogy(par.SNRdB_list,res.VER(d,:),marker_style{d},'LineWidth',2)
    end
  end
  hold off
  grid on
  xlabel('average SNR per receive antenna [dB]','FontSize',12)
  ylabel('vector error rate (VER)','FontSize',12)
  axis([min(par.SNRdB_list) max(par.SNRdB_list) 1e-3 1])
  legend(par.detector,'FontSize',12,'Interpreter','none')
  set(gca,'FontSize',12)
    
end

% -- set of detector functions: 

%% SIMO lower bound
function [idxhat,bithat] = SIMO(par,H,y,s)
  z = y-H*s;
  shat = zeros(par.MT,1);
  for m=1:par.MT
    hm = H(:,m);
    yhat = z+hm*s(m,1);
    shat(m,1) = hm'*yhat/norm(hm,2)^2;    
  end 
  [~,idxhat] = min(abs(shat*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);  
end

%% Maximum-Likelikhood (ML) detection using sphere decoding
function [idxML,bitML] = ML(par,H,y)

  % -- initialization  
  Radius = inf;
  PA = zeros(par.MT,1); % path
  ST = zeros(par.MT,length(par.symbols)); % stack  

  % -- preprocessing
  [Q,R] = qr(H,0);  
  y_hat = Q'*y;    
  
  % -- add root node to stack
  Level = par.MT; 
  ST(Level,:) = abs(y_hat(Level)-R(Level,Level)*par.symbols.').^2;
  
  % -- begin sphere decoder
  while ( Level<=par.MT )          
    % -- find smallest PED in boundary    
    [minPED,idx] = min( ST(Level,:) );
    
    % -- only proceed if list is not empty
    if minPED<inf
      ST(Level,idx) = inf; % mark child as tested        
      NewPath = [ idx ; PA(Level+1:end,1) ]; % new best path
      
      % -- search child
      if ( minPED<Radius )
        % -- valid candidate found
        if ( Level>1 )                  
          % -- expand this best node
          PA(Level:end,1) = NewPath;
          Level = Level-1; % downstep
          DF = R(Level,Level+1:end) * par.symbols(PA(Level+1:end,1)).';
          ST(Level,:) = minPED + abs(y_hat(Level)-R(Level,Level)*par.symbols.'-DF).^2;
        else
          % -- valid leaf found     
          idxML = NewPath;
          bitML = par.bits(idxML',:);
          % -- update radius (radius reduction)
          Radius = minPED;    
        end
      end      
    else
      % -- no more childs to be checked
      Level=Level+1;      
    end    
  end
  
end

%% Maximum Ratio Combining (MRC) detector
function [idxhat,bithat] = MRC(par,H,y)
  shat = H'*y;
  G = real(diag(H'*H));
  [~,idxhat] = min(abs(shat*ones(1,length(par.symbols))-G*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);
end

%% unbiased Zero Forcing (ZF) detector
function [idxhat,bithat] = ZF(par,H,y)
  W = (H'*H)\(H');
  shat = W*y;
  G = real(diag(W*H));
  [~,idxhat] = min(abs(shat*ones(1,length(par.symbols))-G*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);
end

%% unbiased Minimum Mean Squared-Error (MMSE) detector
function [idxhat,bithat] = MMSE(par,H,y,N0)
  W = (H'*H+(N0/par.Es)*eye(par.MT))\(H');
  shat = W*y;
  G = real(diag(W*H));
  [~,idxhat] = min(abs(shat*ones(1,length(par.symbols))-G*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);
end

%% detection via exact SemiDefinite Relaxation (SDR)
%  You need to install CVX to use this
function [idxhat,bithat] = SDR(par,H,y)

  switch par.mod
    case 'QPSK'
      % -- convert to real domain
      yR = [ real(y) ; imag(y) ];
      HR = [ real(H) -imag(H) ; imag(H) real(H) ];   
      % -- preprocessing for SDR  
      T = [HR'*HR , -HR'*yR ; -yR'*HR yR'*yR ];
      N = 2*par.MT+1; 
    case 'BPSK'
      % -- convert to real domain
      yR = [ real(y) ; imag(y) ];
      HR = [ real(H) ; imag(H) ];  
      % -- preprocessing for SDR  
      T = [HR'*HR , -HR'*yR ; -yR'*HR yR'*yR ];
      N = par.MT+1; 
    otherwise
      error('modulation type not supported')
  end  
  
  % -- solve SDP via CVX
  cvx_begin quiet
    variable S(N,N) symmetric;
    S == semidefinite(N);       
    minimize( trace( T*S ) );
    diag(S) == 1;              
  cvx_end
  
  % -- post processing
  [V,U] = eig(S);
  root = V*sqrt(U);
  
  sRhat = sign(root(:,end));  
  switch par.mod
    case 'QPSK'
      shat = sRhat(1:par.MT,1)+1i*sRhat(par.MT+1:end-1,1);
    case 'BPSK'  
      shat = sRhat(1:par.MT,1);
    otherwise
      error('modulation type not supported')
  end
  
  % -- compute outputs
  [~,idxhat] = min(abs(shat*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);
  
end

%% detection via Triangular Approximate SEmidefinite Relaxation (TASER)
% -- Oscar Castañeda, Tom Goldstein, and Christoph Studer,
% -- "Data Detection in Large Multi-Antenna Wireless Systems via
% -- Approximate Semidefinite Relaxation," 
% -- IEEE Transactions on Circuits and Systems I: Regular Papers,
% -- vol. 63, no. 12, pp. 2334-2346, Dec. 2016.
function [idxhat,bithat] = TASER(par,H,y)

  switch par.mod
    case 'QPSK'
      % -- convert to real domain
      yR = [ real(y) ; imag(y) ];
      HR = [ real(H) -imag(H) ; imag(H) real(H) ];   
      % -- preprocessing for SDR  
      T = [HR'*HR , -HR'*yR ; -yR'*HR yR'*yR ];      
    case 'BPSK'
      % -- convert to real domain
      yR = [ real(y) ; imag(y) ];
      HR = [ real(H) ; imag(H) ];  
      % -- preprocessing for SDR  
      T = [HR'*HR , -HR'*yR ; -yR'*HR yR'*yR ];      
    otherwise
      error('modulation not supported')
  end
     
  DInv = diag(diag(T).^-.5);
  Ttilde = DInv*T*DInv;
  stepsize = par.TASER.alphaScale/norm(Ttilde,2);

  % -- use standard gradient on non-convex problem  
  gradf = @(L) 2*tril(L*Ttilde);
  proxg = @(L,t) prox_normalizer(L,diag(DInv).^-1);
  
  % Initialize Ltilde  
  Ltilde = diag(diag(DInv).^-1);
  
  % -- Fast Iterative Soft Thresholding [Beck & Tebouille, 2009]   
  for k = 1:par.TASER.iters
    Ltilde = proxg(Ltilde-stepsize*gradf(Ltilde)); % compute proxy    
  end  
  
  % -- post processing
  sRhat = sign(Ltilde(end,:))';  
  switch par.mod
    case 'QPSK'
      shat = sRhat(1:par.MT,1)+1i*sRhat(par.MT+1:end-1,1);
    case 'BPSK'  
      shat = sRhat(1:par.MT,1);
    otherwise
      error('modulation not supported')
  end
  
  % -- compute outputs
  [~,idxhat] = min(abs(shat*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);
  
end

% normalize columns of Z to have norm equal to its corresponding scale
function Q = prox_normalizer(Z,scale)
  [N,~] = size(Z); 
  Q = Z.*(ones(N,1)*(1./sqrt(sum(abs(Z).^2,1)).*scale'));  
end

%% detection via the Row-By-Row (RBR) method
% -- Hoi-To Wai, Wing-Kin Ma, and Anthony Man-Cho So,
% -- "Cheap Semidefinite Relaxation MIMO Detection using Row-By-Row Block
% -- Coordinate Descent," 
% -- IEEE International Conference on Acoustics, Speech and Signal 
% -- Processing (ICASSP), May 2011, pp. 3256-3259.

function [idxhat,bithat] = RBR(par,H,y)

  % -- convert to real domain
  switch par.mod
    case 'QPSK'
      % -- convert to real domain
      yR = [ real(y) ; imag(y) ];
      HR = [ real(H) -imag(H) ; imag(H) real(H) ];   
      % -- preprocessing for SDR  
      C = [HR'*HR , -HR'*yR ; -yR'*HR yR'*yR ];
      N = 2*par.MT+1; 
    case 'BPSK'
      % -- convert to real domain
      yR = [ real(y) ; imag(y) ];
      HR = [ real(H) ; imag(H) ];  
      % -- preprocessing for SDR  
      C = [HR'*HR , -HR'*yR ; -yR'*HR yR'*yR ];
      N = par.MT+1; 
    otherwise
      error('modulation not supported')
  end

  % -- parameters
  sigma = 1e-2/N;  % Barrier parameter, with value as suggested in the
                   % paper. However, the authors' code uses
                   % sigma = 1e-2/(4*par.MT+1)
  
  % -- initialization
  X = eye(N);
  
  % -- RBR iterations
  for pp=1:par.RBR.iters
    for k=1:N      
      idxset = [1:k-1 k+1:N];      
      c = C(idxset,k);
      z = X(idxset,idxset)*c;      
      gamma = z'*c;      
      if gamma>0
        X(idxset,k) = -1/(2*gamma)*(sqrt(sigma^2+4*gamma)-sigma)*z;
      else
        X(idxset,k) = zeros(N-1,1);
      end
      % -- Ensure that X is symmetric (Very important!)
      X(k,k)=1;
      X(k,idxset) = X(idxset,k);      
    end
  end
  % -- Recover the data from the last column of X.
  shat = sign(X(1:N-1,N));
  
  switch par.mod
    case 'QPSK'
      shat = shat(1:par.MT,1)+1i*shat(par.MT+1:end,1);
    case 'BPSK'  
      shat = shat(1:par.MT,1);
    otherwise
      error('not supported')
  end

  % -- compute outputs  
  [~,idxhat] = min(abs(shat*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);   
  
end

%% ADMM-based Infinity-Norm detection (ADMIN)
% -- Shariar Shahabuddin, Markku Juntti, and Christoph Studer,
% -- "ADMM-based Infinity Norm Detection for Large MU-MIMO: Algorithm and
% -- VLSI Architecture," 
% -- IEEE International Symposium on Circuits, Systems (ISCAS),
% -- May 2017.
function [idxhat,bithat] = ADMIN(par,H,y,N0)

  % -- initialization
  beta = N0/par.Es*par.ADMIN.betaScale; 
  G = H'*H + beta*eye(par.MT);
  [L,D] = ldl(G);
  Dinv = diag(1./diag(D));
  yMF = H'*y;
  zhat = zeros(par.MT,1);
  lambda = zeros(par.MT,1);
  alpha = max(real(par.symbols));
  
  % -- main loop
  for k = 1:par.ADMIN.iters
      shat = L'\(Dinv*(L\(yMF+beta*(zhat-lambda))));
      zhat = projinf(shat+lambda,alpha);
      lambda = lambda-par.ADMIN.gamma*(zhat-shat);
  end
  
  % -- compute outputs
  [~,idxhat] = min(abs(shat*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);
  
end

% project into alpha infinity-norm ball
function sproj = projinf(s,alpha)
  sr = real(s);
  sr = max(min(sr,alpha),-alpha);  
  si = imag(s);
  si = max(min(si,alpha),-alpha);
  sproj = sr + 1i*si;
end

%% BOX detector
function [idxhat,bithat] = BOX(par,H,y)

  % -- initialization
  alpha = max(real(par.symbols));
  shat = H'*y;
  
  % -- apply a projected gradient descent
  for ii=1:par.BOX.iters
    shat = shat-par.BOX.tau*H'*(H*shat-y);
    shat = projinf(shat,alpha);
  end
  
  % -- compute outputs
  [~,idxhat] = min(abs(shat*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);
  
end

%% Optimized Coordinate Descent (OCD) MMSE version
% -- Michael Wu, Chris Dick, Joseph R. Cavallaro, and Christoph Studer,
% -- "High-Throughput Data Detection for Massive MU-MIMO-OFDM Usign
% -- Coordinate Descent," 
% -- IEEE Transactions on Circuits and Systems I: Regular Papers,
% -- vol. 63, no. 12, pp. 2357-2367, Dec. 2016.
function [idxhat,bithat] = OCD_MMSE(par,H,y,N0)

  % -- initialization
  alpha = N0/par.Es; % MMSE regularization; original code had a 0.5 factor

  % -- preprocessing
  dinv = zeros(par.MT,1);
  p = zeros(par.MT,1);
  for uu=1:par.MT
    normH2 = norm(H(:,uu),2)^2;
    dinv(uu,1) = 1/(normH2+alpha);
    p(uu,1) = dinv(uu)*normH2;
  end

  r = y;
  zold = zeros(par.MT,1);
  znew = zeros(par.MT,1);
  deltaz = zeros(par.MT,1);

  % -- OCD loop
  for iters=1:par.OCD_MMSE.iters
    for uu=1:par.MT
      znew(uu) = dinv(uu)*(H(:,uu)'*r)+p(uu)*zold(uu);
      deltaz(uu) = znew(uu)-zold(uu);
      r = r - H(:,uu)*deltaz(uu);
      zold(uu) = znew(uu);
    end
  end

  % -- compute outputs
  [~,idxhat] = min(abs(znew*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);

end

%% Optimized Coordinate Descent (OCD) BOX version
% -- Michael Wu, Chris Dick, Joseph R. Cavallaro, and Christoph Studer,
% -- "High-Throughput Data Detection for Massive MU-MIMO-OFDM Usign
% -- Coordinate Descent," 
% -- IEEE Transactions on Circuits and Systems I: Regular Papers,
% -- vol. 63, no. 12, pp. 2357-2367, Dec. 2016.
function [idxhat,bithat] = OCD_BOX(par,H,y)

  % -- initialization
  alpha = max(real(par.symbols));

  % -- preprocessing
  dinv = zeros(par.MT,1);
  p = zeros(par.MT,1);
  for uu=1:par.MT
    normH2 = norm(H(:,uu),2)^2;
    dinv(uu,1) = 1/normH2;
    p(uu,1) = dinv(uu)*normH2;
  end

  r = y;
  zold = zeros(par.MT,1);
  znew = zeros(par.MT,1);
  deltaz = zeros(par.MT,1);

  % -- OCD loop
  for iters=1:par.OCD_BOX.iters
    for uu=1:par.MT
      tmp = dinv(uu)*(H(:,uu)'*r)+p(uu)*zold(uu);
      znew(uu) = projinf(tmp,alpha);
      deltaz(uu) = znew(uu)-zold(uu);
      r = r - H(:,uu)*deltaz(uu);
      zold(uu) = znew(uu);
    end
  end

  % -- compute outputs
  [~,idxhat] = min(abs(znew*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);

end

%% K-Best detector
function [idxhat,bithat] = KBEST(par,H,y)

  % -- preprocessing
  [Q,R] = qr(H);
  y_hat = Q'*y;

  % -- Initialize Partial Euclidean Distance (PED) with last TX symbol
  PED_list=abs(par.symbols*R(par.MT,par.MT) - y_hat(par.MT)).^2;
  [PED_list,idx]=sort(PED_list);
  s=par.symbols(:,idx);
  % -- take the K-best
  s=s(:,1:min(par.KBEST.K,length(PED_list)));
  Kbest_PED_list=PED_list(1:min(par.KBEST.K,length(PED_list)));

  % -- for each TX symbol
  for Level=par.MT-1:-1:1
    PED_list=[];
    % -- obtain the cumulative Euclidean distance considering the K-best
    %    previous nodes
    for k=1:length(Kbest_PED_list)
      tmp=Kbest_PED_list(k)+abs(par.symbols*R(Level,Level)-y_hat(Level) + ...
          R(Level,Level+1:par.MT)*s(:,k)).^2;
      PED_list=[PED_list,tmp];
    end
    % -- sort in ascending order
    s=[kron(ones(1,length(Kbest_PED_list)),par.symbols); ...
       kron(s,ones(1,length(par.symbols)))];
    [PED_list,idx]=sort(PED_list);
    s=s(:,idx);
    % take the K-best
    s=s(:,1:min(par.KBEST.K,length(PED_list)));
    Kbest_PED_list=PED_list(1:min(par.KBEST.K,length(PED_list)));
  end
  % -- take the best
  s=s(:,1);
  
  % -- compute outputs
  idxhat=zeros(par.MT,1);
  for i=[1:par.MT]
    idxhat(i,1)= find(s(i)==par.symbols);
  end  
  bithat = par.bits(idxhat,:);
  
end

%% Line of sight channel generation.
%  Special thanks to Sven Jacobsson for this function
function H_pwm = los(par)

  U = par.MT;
  B = par.MR;

  c = 3e8; % speed of light [m/s]
  lambda =  c / 2e9; % carrier wavelength [m]
  delta = .5; % antenna spacing
    
  % place users randomly in a circular sector [-angSec/2,angSec/2],
  % using the Hash Slinging Slasher method
  % - generate angular separations of at least angSepMin
  UE_sep = zeros(U-1,1);
  par.angSec = 120;
  sectorAvail = par.angSec;
  par.angSepMin = 1;
  for uu = 1:U-1 % user loop
    UE_sep(uu) = unifrnd(par.angSepMin,sectorAvail/(U-uu));
    sectorAvail = sectorAvail - UE_sep(uu);
  end
  % - permute angular separations
  UE_sep = UE_sep(randperm(U-1));
  % - convert angular separations into angles
  UE_ang = [0; cumsum(UE_sep)];
  UE_ang = UE_ang - (max(UE_ang)-min(UE_ang))/2; % center users
  % -- wiggle users up to the angular space available
  UE_angLeft = par.angSec-(max(UE_ang)-min(UE_ang));
  UE_ang = UE_ang + unifrnd(-UE_angLeft/2,UE_angLeft/2);    
 
  % distance spread  
  par.d_spread = 0; % distance spread
  d_max = 150 + par.d_spread; % max user distance [m]
  d_min = 150 - par.d_spread; % min user distance [m]     
  if par.d_spread > 0
    d_avg = 2/3*(d_max^3-d_min^3)/(d_max^2-d_min^2); % avg user distance [m]
  else
    d_avg = d_max;
  end
  d_UE = sqrt((d_max^2-d_min^2)*rand(U,1) + d_min^2);% UE dist [m]
 
  broadside_BS_deg = 0; % broadside of BS antenna array  [deg]
  aod_UE = UE_ang + broadside_BS_deg;
 
  coord_BS = [0, 0]; % BS coord.
  coord_UE = ones(U,1)*coord_BS + ...
             (d_UE*ones(1,2)).*[cosd(aod_UE), sind(aod_UE)]; % UE coord.
     
  d_ant_BS = delta * lambda; % distance between BS antenna elements [m]
 
  % array rotation
  Omega_BS_deg = wrapTo360(90 - broadside_BS_deg); % BS array rotation [deg]
  Omega_BS_rad = pi/180 * Omega_BS_deg; % BS array rotation [rad]
 
  % antenna elem. coordinates
  x_BS = coord_BS(1) + d_ant_BS*((1:B) - (B+1)/2)*cos(pi-Omega_BS_rad);
  y_BS = coord_BS(2) + d_ant_BS*((1:B) - (B+1)/2)*sin(pi-Omega_BS_rad);
  x_UE = coord_UE(:,1);
  y_UE = coord_UE(:,2);
 
  % coordinates
  xx_BS = ones(U,1)*x_BS; yy_BS = ones(U,1)*y_BS;
  xx_UE = x_UE*ones(1,B); yy_UE = y_UE*ones(1,B);
     
  % reference distance
  d_ref = sqrt((xx_BS - xx_UE).^2 + (yy_BS - yy_UE).^2);
 
  % angles
  theta_BS = Omega_BS_rad - pi/2 + atan2((yy_UE-yy_BS),(xx_UE-xx_BS));
     
  % distances between UE and BS antenna elements
  dd_ant_BS = d_ant_BS*ones(U,1)*((1:B)-1); 
  tt_BS = theta_BS(:,1)*ones(1,B);
     
  % distance according to PWM model
  d_pwm = d_ref(:,1)*ones(1,B) - dd_ant_BS.*sin(tt_BS);
 
  % channel matrix
  H_pwm = d_avg./d_pwm .* exp(-1i*2*pi*d_pwm/lambda);
  H_pwm = H_pwm.';
    
end
 
function lon = wrapTo360(lon)
 
  positiveInput = (lon > 0);
  lon = mod(lon, 360);
  lon((lon == 0) & positiveInput) = 360;
 
end
