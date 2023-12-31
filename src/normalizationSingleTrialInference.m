function [dMapPair,dMapInd] = normalizationSingleTrialInference(spikes,parameters)
%% normalizationSingleTrialInference Finds the Maximum a Priori estimates for the normalization signal in a Ratio of Gaussians model
%   INPUT
%       spikes (2,number of stimuli, number of trials) - the spike responses
%       parameters (1,19) - the fit parameters for the Ratio of Gaussians model
%   OUTPUT
%       dMapPair (2, number of stimuli, number of trials) - pairwise MAP estimate of the normalization signal
%       dMapInd (2, number of stimuli, number of trials) - independent MAP estimate of normalization signal
%%


	%% If rho_N=rho_D=0, then dMapPair cannot be computed from below but is identical to independent RoG
	if (parameters.rho(1)==0 && parameters.rho(2)==0)
		dMapPair = [indsingletrialinfer(spikes,parameters.mu_n,parameters.mu_d,parameters.var_n,parameters.var_d)];
        dMapInd = NaN(size(dMapPair));
		return
	end

	Cfs = polycoeffs(spikes,parameters.mu_n,parameters.mu_d,parameters.var_n,parameters.var_d,parameters.rho);
	d1 = real(d1_map_internal(Cfs)); %Assume all solutions are real
	d2 = real(d2_map_internal(Cfs));

	%% Find which solution minimizes the neglogposterior
	NLP = neglogpost(Cfs,d1,d2);
	[~,min_ind] = min(NLP,[],1);

	%% Extract the linear indices from this for ease of combining into one vector without looping
	[~,ns,nt] = size(spikes);
	[ids,idt] = ndgrid(1:ns,1:nt);
	linind = sub2ind(size(d1),reshape(squeeze(min_ind),1,ns,nt),reshape(ids,1,ns,nt),reshape(idt,1,ns,nt));

	dMapPair = [d1(linind);d2(linind)];
% 	if nargout > 1
		dMapInd = [indsingletrialinfer(spikes,parameters.mu_n,parameters.mu_d,parameters.var_n,parameters.var_d)];
% 	end
	% unc = (1./dmin.^2+Cfs(1:2,:,:)).^(-1); %% Uncertainty from Laplace approximation
	% nlp_min2 = neglogpost(Cfs,dmin(1,:,:),dmin(2,:,:));
end

function coefs =  polycoeffs(spikes,mu_n,mu_d,var_n,var_d,rho)

	RN = (1-rho(1)^2);
	RD = (1-rho(2)^2);

	VN = var_n*RN;
	VD = var_d*RD;
	VN12 = sqrt(var_n(1,:).*var_n(2,:))*RN;
	VD12 = sqrt(var_d(1,:).*var_d(2,:))*RD;

	%% Attempting to speed up computation using bsxfun
	%% A = R^2/(var_N*(1-rho_N^2)+1/(var_D*(1-rho_D^2))
	A = bsxfun(@rdivide,spikes.^2,VN)+1./VD;

	%% B1 = -2[(mu_N1*R1)/(var_N1*(1-rho_N^2)+mu_D1/(var_D1*(1-rho_D^2)))]+2[mu_N2*R_1/(sd_N1*sd_N2*(1-rho_N^2))+mu_D2/(sd_D1*sd_D2*(1-rho_D^2))]
	%% Similarly for B2
	B = -2*(bsxfun(@rdivide,bsxfun(@times,mu_n,spikes),VN)+bsxfun(@rdivide,mu_d,VD))...
		+2*(rho(1)*bsxfun(@rdivide,bsxfun(@times,mu_n([2 1],:),spikes),VN12)+rho(2)*bsxfun(@rdivide,mu_d([2 1],:),VD12));

	%% C = -2*rho_N*R_1*R_2/(var_N1*var_N2*(1-rho_N^2))-2*rho_D/(var_D1*var_D2*(1-rho_D^2))
	C = -2*(rho(1)*bsxfun(@rdivide,bsxfun(@times,spikes(1,:,:),spikes(2,:,:)),VN12)+rho(2)./VD12);

	coefs = [A;B;C];
end

function nlp = neglogpost(cfs,d1,d2)

	a1 = cfs(1,:,:);
	a2 = cfs(2,:,:);
	b1 = cfs(3,:,:);
	b2 = cfs(4,:,:);
	c = cfs(5,:,:);

	nlp = -log(abs(d1))-log(abs(d2))+0.5*(bsxfun(@times,d1.^2,a1)+bsxfun(@times,d1,b1)...
											+bsxfun(@times,d2.^2,a2)+bsxfun(@times,d2,b2)...
											+bsxfun(@times,d1.*d2,c));
end

%% % % D Map Functions
%%%%---------------------------------------------------------------------------------------------------------------------%%%%
%% % %
function mu_map = indsingletrialinfer(r,mu_n,mu_d,var_n,var_d)
	% % %         Computes single trial inference using estimated
	% % %         mu_n,mu_d,var_n,var_d and raw firing rate inputs (r)
	% % %         mu_map (maximum a posterior estimate) is primarily what is
	% % %           being used, mu_dr and var_dr are the estimates
	% % %           given in the JNeuroscience paper but are quantitatively
	% % %           very similar to the MAP estimate and are used to compute
	% % %           the MAP. They are returned by this function for testing
	% % %           purposes
	% % %         Formula:
	% % %                       r*mu_{n}*var_{d}+mu_{d}*var_{n}
	% % %         mu_{d|r} =    ---------------------------------
	% % %                           r^2*var_{d}+var_{n}
	% % %
	% % %                               var_{d}*var{n}
	% % %         var_{d|r} =    ---------------------------------
	% % %                           r^2*var_{d}+var_{n}
	% % %
	% % %         mu_{map} =
	% % %                       1/2*mu_{d|r}+1/2*mu_{d|r}*sqrt(1+var_{d|r}/(1/2*mu_{d_r})^2)
	% % %
			t0 = r.^2.*var_d+var_n;
			t1 = (r.*mu_n.*var_d+mu_d.*var_n)./(t0);
			t2 = var_d.*var_n./(t0);


			mu_map = 0.5*t1+sqrt(0.25*t1.^2+t2);

	end

function d1 = d1_map_internal(cfs)
	%D1_MAP
	%    D1 = D1_MAP(A1,A2,B1,B2,C)

	%    This function was generated by the Symbolic Math Toolbox version 8.6.

	a1 = cfs(1,:,:);
	a2 = cfs(2,:,:);
	b1 = cfs(3,:,:);
	b2 = cfs(4,:,:);
	c = cfs(5,:,:);
	% c2 = c;
	% c2(isnan(c2)) = [];
	% if all(c==0,'all')
	%     [ns,nt] = size(a1,[2 3]);
	%     d1 = NaN(4,ns,nt);
	%     return
	% end

	t2 = b1.*c;
	t3 = a2.^2;
	t4 = b2.^2;
	t5 = c.^2;
	t6 = a1.*a2.*4.0;
	t7 = a1.*b2.*2.0;
	t10 = 1.0./a1;
	t11 = 1.0./c;
	t12 = a1.*a2.*8.0;
	t13 = a1.*a2.*1.6e+1;
	t14 = a1.*b2.*8.0;
	t17 = sqrt(3.0);
	t18 = sqrt(6.0);
	t28 = a1.*a2.*b2.*-8.0;
	t8 = t2.*2.0;
	t9 = b2.*t2;
	t15 = -t2;
	t19 = b2.*t5;
	t21 = -t5;
	t22 = a1.*t4.*2.0;
	t23 = a2.*t5.*2.0;
	t24 = b2.*t12;
	t25 = a1.*t3.*8.0;
	t44 = t10.*t11.*(t2-t7).*(-1.0./2.0);
	t16 = -t8;
	t20 = a2.*t8;
	t26 = -t22;
	t27 = -t23;
	t29 = t7+t15;
	t30 = t6+t21;
	t35 = -1.0./(t23-t25);
	t36 = 1.0./(t23-t25).^2;
	t43 = (a1.*-8.0)./(t23-t25);
	t45 = (a1.*8.0)./(t23-t25);
	t46 = (a1.*-9.6e+1)./(t23-t25);
	t47 = (t8-t14)./(t23-t25);
	t31 = t14+t16;
	t32 = t25+t27;
	t33 = t9+t12+t26;
	t34 = t9+t13+t26;
	t37 = t35.*t36;
	t38 = t36.^2;
	t39 = t19+t20+t28;
	t40 = t39.^2;
	t41 = t39.^3;
	t48 = t34.*t35;
	t49 = (t39.*(-1.0./4.0))./(t23-t25);
	t50 = t39./(t23.*4.0-t25.*4.0);
	t56 = t36.*t39.*(t8-t14).*-3.0;
	t57 = t36.*t39.*(t8-t14).*3.0;
	t58 = t36.*t39.*(t8-t14).*(-1.0./4.0);
	t59 = (t34.*t36.*t39)./2.0;
	t42 = t40.^2;
	t51 = t36.*t40.*(3.0./8.0);
	t52 = t41.*1.0./(t23-t25).^3.*(-1.0./8.0);
	t60 = t34.*t40.*1.0./(t23-t25).^3.*(-3.0./4.0);
	t61 = t34.*t40.*1.0./(t23-t25).^3.*(3.0./4.0);
	t62 = t34.*t40.*1.0./(t23-t25).^3.*(-1.0./1.6e+1);
	t53 = t38.*t42.*(3.0./2.56e+2);
	t54 = t38.*t42.*(9.0./6.4e+1);
	t63 = t48+t51;
	t71 = t47+t52+t59;
	t55 = -t54;
	t64 = t63.^2;
	t65 = t63.^3;
	t72 = t71.^2;
	t77 = t45+t53+t58+t62;
	t66 = t64.^2;
	t67 = t65.*2.0;
	t69 = t65./2.7e+1;
	t73 = t72.^2;
	t74 = t72.*2.7e+1;
	t76 = t72./2.0;
	t78 = t77.^2;
	t79 = t77.^3;
	t81 = t65.*t72.*4.0;
	t83 = t63.*t77.*(4.0./3.0);
	t84 = t63.*t77.*7.2e+1;
	t89 = t63.*t72.*t77.*1.44e+2;
	t68 = -t67;
	t70 = -t69;
	t75 = t73.*2.7e+1;
	t80 = t79.*2.56e+2;
	t82 = -t81;
	t85 = t66.*t77.*1.6e+1;
	t86 = -t83;
	t87 = -t84;
	t88 = t64.*t78.*1.28e+2;
	t90 = -t89;
	t91 = t75+t80+t82+t85+t88+t90;
	t92 = sqrt(t91);
	t93 = t17.*t92.*3.0;
	t94 = (t17.*t92)./1.8e+1;
	t95 = t68+t74+t87+t93;
	t97 = t70+t76+t86+t94;
	t96 = sqrt(t95);
	t98 = t97.^(1.0./3.0);
	t100 = 1.0./t97.^(1.0./6.0);
	t99 = t98.^2;
	t102 = t63.*t98.*6.0;
	t103 = t18.*t71.*t96.*3.0;
	t101 = t99.*9.0;
	t104 = -t103;
	t105 = t46+t55+t57+t61+t64+t101+t102;
	t106 = sqrt(t105);
	t107 = 1.0./t105.^(1.0./4.0);
	t108 = t64.*t106;
	t110 = t77.*t106.*1.2e+1;
	t111 = t101.*t106;
	t112 = t99.*t106.*-9.0;
	t113 = (t100.*t106)./6.0;
	t115 = t63.*t98.*t106.*1.2e+1;
	t109 = -t108;
	t114 = -t113;
	t116 = t103+t109+t110+t112+t115;
	t117 = t104+t109+t110+t112+t115;
	t118 = sqrt(t116);
	t119 = sqrt(t117);
	t120 = (t100.*t107.*t118)./6.0;
	t121 = (t100.*t107.*t119)./6.0;
	t122 = -t120;
	t123 = t49+t113+t120;
	t125 = t49+t114+t121;
	t126 = t50+t113+t121;
	t124 = t49+t113+t122;
	d1 = [t44-(t10.*t11.*t33.*t126)./4.0+(t10.*t11.*t39.*t126.^2)./4.0-(a2.*t10.*t11.*t126.^3.*(t5-t6))./2.0;t44+(t10.*t11.*t39.*(t50+t113-t121).^2)./4.0-(t10.*t11.*t33.*(t50+t113-t121))./4.0-(a2.*t10.*t11.*(t5-t6).*(t50+t113-t121).^3)./2.0;t44-(t10.*t11.*t33.*(t50+t114+t120))./4.0+(t10.*t11.*t39.*(t50+t114+t120).^2)./4.0-(a2.*t10.*t11.*(t5-t6).*(t50+t114+t120).^3)./2.0;t44+(t10.*t11.*t33.*t123)./4.0+(t10.*t11.*t39.*t123.^2)./4.0+(a2.*t10.*t11.*t123.^3.*(t5-t6))./2.0];

end

function d2 = d2_map_internal(cfs)
	%D2_MAP
	%    D2 = D2_MAP(A1,A2,B1,B2,C)

	%    This function was generated by the Symbolic Math Toolbox version 8.6.
	% [ns,nt] = size(a1);
	%%%
	a1 = cfs(1,:,:);
	a2 = cfs(2,:,:);
	b1 = cfs(3,:,:);
	b2 = cfs(4,:,:);
	c = cfs(5,:,:);

	% c2 = c;
	% c2(isnan(c2)) = [];
	% if all(c2==0,'all')
	%     [ns,nt] = size(a1,[2 3]);
	%     d2 = NaN(4,ns,nt);
	%     return
	% end
	%%%
	t2 = a2.^2;
	t3 = b2.^2;
	t4 = c.^2;
	t5 = b1.*c.*2.0;
	t6 = b1.*b2.*c;
	t7 = a1.*a2.*1.6e+1;
	t8 = a1.*b2.*8.0;
	t10 = sqrt(3.0);
	t11 = sqrt(6.0);
	t20 = a1.*a2.*b2.*-8.0;
	t9 = -t5;
	t12 = b2.*t4;
	t13 = a2.*t5;
	t14 = a1.*t3.*2.0;
	t15 = a2.*t4.*2.0;
	t16 = a2.*t8;
	t17 = a1.*t2.*8.0;
	t18 = -t14;
	t19 = -t15;
	t21 = t8+t9;
	t24 = -1.0./(t15-t17);
	t25 = 1.0./(t15-t17).^2;
	t28 = t12+t13+t20;
	t32 = (a1.*-8.0)./(t15-t17);
	t33 = (a1.*8.0)./(t15-t17);
	t34 = (a1.*-9.6e+1)./(t15-t17);
	t35 = (t5-t8)./(t15-t17);
	t22 = t17+t19;
	t23 = t6+t7+t18;
	t26 = t24.*t25;
	t27 = t25.^2;
	t29 = t28.^2;
	t30 = t28.^3;
	t37 = (t28.*(-1.0./4.0))./(t15-t17);
	t43 = t25.*t28.*(t5-t8).*-3.0;
	t44 = t25.*t28.*(t5-t8).*3.0;
	t45 = t25.*t28.*(t5-t8).*(-1.0./4.0);
	t31 = t29.^2;
	t36 = t23.*t24;
	t38 = t25.*t29.*(3.0./8.0);
	t39 = t30.*1.0./(t15-t17).^3.*(-1.0./8.0);
	t46 = (t23.*t25.*t28)./2.0;
	t47 = t23.*t29.*1.0./(t15-t17).^3.*(-3.0./4.0);
	t48 = t23.*t29.*1.0./(t15-t17).^3.*(3.0./4.0);
	t49 = t23.*t29.*1.0./(t15-t17).^3.*(-1.0./1.6e+1);
	t40 = t27.*t31.*(3.0./2.56e+2);
	t41 = t27.*t31.*(9.0./6.4e+1);
	t50 = t36+t38;
	t58 = t35+t39+t46;
	t42 = -t41;
	t51 = t50.^2;
	t52 = t50.^3;
	t59 = t58.^2;
	t64 = t33+t40+t45+t49;
	t53 = t51.^2;
	t54 = t52.*2.0;
	t56 = t52./2.7e+1;
	t60 = t59.^2;
	t61 = t59.*2.7e+1;
	t63 = t59./2.0;
	t65 = t64.^2;
	t66 = t64.^3;
	t68 = t52.*t59.*4.0;
	t70 = t50.*t64.*(4.0./3.0);
	t71 = t50.*t64.*7.2e+1;
	t76 = t50.*t59.*t64.*1.44e+2;
	t55 = -t54;
	t57 = -t56;
	t62 = t60.*2.7e+1;
	t67 = t66.*2.56e+2;
	t69 = -t68;
	t72 = t53.*t64.*1.6e+1;
	t73 = -t70;
	t74 = -t71;
	t75 = t51.*t65.*1.28e+2;
	t77 = -t76;
	t78 = t62+t67+t69+t72+t75+t77;
	t79 = sqrt(t78);
	t80 = t10.*t79.*3.0;
	t81 = (t10.*t79)./1.8e+1;
	t82 = t55+t61+t74+t80;
	t84 = t57+t63+t73+t81;
	t83 = sqrt(t82);
	t85 = t84.^(1.0./3.0);
	t87 = 1.0./t84.^(1.0./6.0);
	t86 = t85.^2;
	t89 = t50.*t85.*6.0;
	t90 = t11.*t58.*t83.*3.0;
	t88 = t86.*9.0;
	t91 = -t90;
	t92 = t34+t42+t44+t48+t51+t88+t89;
	t93 = sqrt(t92);
	t94 = 1.0./t92.^(1.0./4.0);
	t95 = t51.*t93;
	t97 = t64.*t93.*1.2e+1;
	t98 = t88.*t93;
	t99 = t86.*t93.*-9.0;
	t100 = (t87.*t93)./6.0;
	t102 = t50.*t85.*t93.*1.2e+1;
	t96 = -t95;
	t101 = -t100;
	t103 = t90+t96+t97+t99+t102;
	t104 = t91+t96+t97+t99+t102;
	t105 = sqrt(t103);
	t106 = sqrt(t104);
	t107 = (t87.*t94.*t105)./6.0;
	t108 = (t87.*t94.*t106)./6.0;
	d2 = [t37+t101-t108;t37+t101+t108;t37+t100-t107;t37+t100+t107];


	% d2(d2<0) = NaN;
	% d2 = reshape(d2,4,ns,nt);
end
