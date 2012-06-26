c
c $Id: subgotm.f,v 1.12 2008-12-18 16:28:51 georg Exp $
c
c gotm module
c
c contents :
c
c revision log :
c
c 10.08.2003    ggu     call gotm_init
c 05.10.2004    ggu     new administration routine turb_closure, Munk-And.
c 23.03.2006    ggu     changed time step to real
c 20.11.2006    ggu     new version of keps, for gotm changed common blocks
c 20.10.2007    ccf     new version of gotm (4.0.0)
c 10.04.2008    ggu     integrated in main branch
c 18.09.2008    ccf     bug fix for m2 in setm2n2
c 02.12.2008    ggu     bug in gotm_init: no limiting values for initialization
c 18.12.2008    ggu     bug in GOTM module and setm2n2() corrected
c 16.02.2011    ggu     write n2max to info file, profiles in special node
c 29.03.2013    ggu     avoid call to areaele -> ev(10,ie)
c
c**************************************************************

	subroutine turb_closure

c administers turbulence closure

	real getpar,areaele

	integer iturb
	save iturb
	data iturb / 0 /

	if( iturb .lt. 0 ) return

	if( iturb .eq. 0 ) then
	  iturb = nint(getpar('iturb'))
	  if( iturb .le. 0 ) iturb = -1
	  if( iturb .lt. 0 ) return
	  write(*,*) 'starting turbulence model: ',iturb
	end if

	if( iturb .eq. 1 ) then		!Gotm
	  call gotm_shell
	else if( iturb .eq. 2 ) then	!keps
	  call keps_shell
	else if( iturb .eq. 3 ) then	!Munk Anderson
	  call munk_anderson_shell
	else
	  write(6,*) 'Value iturb not possible: ',iturb
	  stop 'error stop turb_closure: iturb'
	end if

	end

c**************************************************************

	subroutine munk_anderson_shell

c computes turbulent quantities with Munk - Anderson model

	implicit none

	include 'param.h'

        integer itanf,itend,idt,nits,niter,it
        common /femtim/ itanf,itend,idt,nits,niter,it
        integer nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        common /nkonst/ nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        integer nlvdi,nlv
        common /level/ nlvdi,nlv
        real grav,fcor,dcor,dirn,rowass,roluft
        common /pkonst/ grav,fcor,dcor,dirn,rowass,roluft

c---------------------------------------------------------------
c aux arrays superposed onto other aux arrays
c---------------------------------------------------------------

	real shearf2(nlvdim,nkndim)
	common /saux1/shearf2
	real buoyf2(nlvdim,nkndim)
	common /saux2/buoyf2
	real richard(nlvdim,nkndim)
	common /saux3/richard

	real visv(0:nlvdim,nkndim)
	common /visv/visv
	real difv(0:nlvdim,nkndim)
	common /difv/difv

	integer k,l
	integer nlev
	integer mode
	real h(nlvdim)
	real ri,vis,dif
	real diftur,vistur
	real a,b,alpha,beta

	real getpar

	integer icall
	save icall
	data icall / 0 /

c------------------------------------------------------
c initialization
c------------------------------------------------------

	if( icall .lt. 0 ) return

	if( icall .eq. 0 ) then
	  write(*,*) 'starting Munk Anderson turbulence model'
	end if

	icall = icall + 1

c------------------------------------------------------
c set up buoyancy frequency and shear frequency
c------------------------------------------------------

	call setm2n2(nlvdim,buoyf2,shearf2)

c------------------------------------------------------
c set up parameters
c------------------------------------------------------

	mode = +1
	a = 10.
	b = 3.33
	alpha = -1./2.
	beta = -3./2.
	vistur = getpar('vistur')
	diftur = getpar('diftur')

c------------------------------------------------------
c compute richardson number for each water column
c------------------------------------------------------

	do k=1,nkn

	    call dep3dnod(k,mode,nlev,h)

	    do l=1,nlev-1
	      ri = buoyf2(l,k) / shearf2(l,k)
	      vis = vistur*(1.+a*ri)**alpha
	      dif = diftur*(1.+b*ri)**beta

	      visv(l,k) = vis
	      difv(l,k) = dif
	      richard(l,k) = ri
	    end do

            if( nlev .eq. 1 ) then
	      visv(0,k) = vistur
	      difv(0,k) = diftur
	      visv(1,k) = vistur
	      difv(1,k) = diftur
	      richard(1,k) = 0.
            else
	      visv(0,k) = visv(1,k)
	      difv(0,k) = difv(1,k)
	      visv(nlev,k) = visv(nlev-1,k)
	      difv(nlev,k) = difv(nlev-1,k)
	      richard(nlev,k) = richard(nlev-1,k)
            end if

	end do

c------------------------------------------------------
c end of routine
c------------------------------------------------------

	end

c**************************************************************

	subroutine gotm_shell

c computes turbulent quantities with GOTM model

	implicit none

	include 'param.h'

	integer ndim
	parameter(ndim=nlvdim)

	double precision dt
	double precision u_taus,u_taub

	double precision hh(0:ndim)
	double precision nn(0:ndim), ss(0:ndim)

	double precision num(0:ndim), nuh(0:ndim)
	double precision ken(0:ndim), dis(0:ndim)
	double precision len(0:ndim)

	double precision num_old(0:ndim), nuh_old(0:ndim)
	double precision ken_old(0:ndim), dis_old(0:ndim)
	double precision len_old(0:ndim)

        double precision numv(0:nlvdim,nkndim)  !viscosity (momentum)
        double precision nuhv(0:nlvdim,nkndim)  !diffusivity (scalars)
        double precision tken(0:nlvdim,nkndim)  !turbulent kinetic energy
        double precision eps (0:nlvdim,nkndim)  !dissipation rate
        double precision rls (0:nlvdim,nkndim)  !length scale
 
        common /numv/numv
        common /nuhv/nuhv
        common /tken_gotm/tken
        common /eps_gotm/eps
        common /rls_gotm/rls
 
        save /numv/,/nuhv/,/tken_gotm/,/eps_gotm/,/rls_gotm/

        integer itanf,itend,idt,nits,niter,it
        common /femtim/ itanf,itend,idt,nits,niter,it
        integer nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        common /nkonst/ nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        integer nlvdi,nlv
        common /level/ nlvdi,nlv
        real grav,fcor,dcor,dirn,rowass,roluft
        common /pkonst/ grav,fcor,dcor,dirn,rowass,roluft

	integer nen3v(1)
	common /nen3v/nen3v
	real rhov(nlvdim,nkndim)
	common /rhov/rhov

c---------------------------------------------------------------
c aux arrays superposed onto other aux arrays
c---------------------------------------------------------------

	real shearf2(nlvdim,nkndim)
	common /saux1/shearf2
	real buoyf2(nlvdim,nkndim)
	common /saux2/buoyf2
	real taub(1)
	common /v1v/taub
	real areaac(1)
	common /v2v/areaac

	integer ilhkv(1)
	common /ilhkv/ilhkv
	real uprv(nlvdim,nkndim)
	common /uprv/uprv
	real vprv(nlvdim,nkndim)
	common /vprv/vprv
        real tauxnv(1),tauynv(1)
        common /tauxnv/tauxnv,/tauynv/tauynv

	real visv(0:nlvdim,nkndim)
	common /visv/visv
	real difv(0:nlvdim,nkndim)
	common /difv/difv

	integer ioutfreq,ks
	integer k,l
	integer laux
	integer nlev
	real g
	real czdef,taubot
	save czdef

	real h(nlvdim)
	double precision depth		!total depth [m]
	double precision z0s,z0b	!surface/bottom roughness length [m]
	double precision rlmax
	integer nltot
	logical bwrite

        real z0bk(nkndim)               !bottom roughenss on nodes
        common /z0bk/z0bk
	real charnock_val		!emp. Charnok constant (1955)
	parameter(charnock_val=1400.)	!default value = 1400.
	double precision z0s_min	!minimum value of z0s
	parameter(z0s_min=0.02)
	real ubot,vbot,rr

	real dtreal
	real getpar,areaele

	integer namlst
	character*80 fn	
	integer icall
	save icall
	data icall / 0 /

c------------------------------------------------------
c documentation
c------------------------------------------------------

c total stress :  tau_x = a |u| u   tau_y = a |u| v
c tau_tot^2 = a^2 |u|^2 ( u^2 + v^2 ) a^2 |u|^4
c tau_tot = sqrt(tau_x^2+tau_y^2) = a |u|^2
c
c u_taus=sqrt(sqrt(tx*tx+ty*ty))	(friction velocity)

c------------------------------------------------------
c initialization
c------------------------------------------------------

	if( icall .lt. 0 ) return

	if( icall .eq. 0 ) then
	  czdef = getpar('czdef')
	  write(*,*) 'starting GOTM turbulence model'

c         --------------------------------------------------------
c         Initializes gotm arrays 
c         --------------------------------------------------------

	  call gotm_init

c         --------------------------------------------------------
c         Get file name containing GOTM turbulence model parameters
c         --------------------------------------------------------

          call getfnm('gotmpa',fn)

	  call init_gotm_turb(10,fn,ndim)

	end if

	icall = icall + 1

	call get_timestep(dtreal)
	dt = dtreal
	g = grav

c------------------------------------------------------
c set up bottom stress on nodes
c------------------------------------------------------

	call bnstress(czdef,taub,areaac)

c------------------------------------------------------
c set up buoyancy frequency and shear frequency
c------------------------------------------------------

	call setm2n2(nlvdim,buoyf2,shearf2)

c------------------------------------------------------
c call gotm for each water column
c------------------------------------------------------

	rlmax = 0.
	nltot = 0

	do k=1,nkn

	    call dep3dnod(k,+1,nlev,h)

            if( nlev .eq. 1 ) goto 1

c           ------------------------------------------------------
c           update boyancy and shear-frequency vectors
c           ------------------------------------------------------

	    do l=1,nlev-1
	      laux = nlev - l
	      nn(laux) = buoyf2(l,k)
	      ss(laux) = shearf2(l,k)
	    end do
	    nn(0) = 0.
	    nn(nlev) = 0.
	    ss(0) = ss(1)
	    ss(nlev) = ss(nlev-1)

c           ------------------------------------------------------
c           compute layer thickness and total depth
c           ------------------------------------------------------

	    depth = 0.
	    do l=1,nlev
	      hh(nlev-l+1) = h(l)
	      depth = depth + h(l)
	    end do

c           ------------------------------------------------------
c           compute surface friction velocity (m/s)
c           ------------------------------------------------------

	    u_taus = sqrt( sqrt( tauxnv(k)**2 + tauynv(k)**2 ) )

	    z0s = charnock_val*u_taus**2/g
	    z0s = max(z0s,z0s_min)

c           ------------------------------------------------------
c           compute bottom friction velocity (m/s)
c           ------------------------------------------------------

	    z0b = z0bk(k)
	    u_taub = sqrt( taub(k) )

	    ubot = uprv(nlev,k)
  	    vbot = vprv(nlev,k)
	    rr = 0.4/(log((z0b+hh(1)/2)/z0b))
            u_taub = rr*sqrt( ubot*ubot + vbot*vbot )

c           ------------------------------------------------------
c           update 1-dimensional vectors
c           ------------------------------------------------------

	    do l=0,nlev
	      num(l) = numv(l,k)
	      nuh(l) = nuhv(l,k)
	      ken(l) = tken(l,k)
	      dis(l) = eps(l,k)
	      len(l) = rls(l,k)
	      num_old(l) = numv(l,k)
	      nuh_old(l) = nuhv(l,k)
	      ken_old(l) = tken(l,k)
	      dis_old(l) = eps(l,k)
	      len_old(l) = rls(l,k)
	    end do

	    !call save_gotm_init

c           ------------------------------------------------------
c           call GOTM turbulence routine
c           ------------------------------------------------------

 	    call do_gotm_turb   (
     &				  nlev,dt,depth
     &				 ,u_taus,u_taub
     &				 ,z0s,z0b,hh
     &	                         ,nn,ss
     &				 ,num,nuh,ken,dis,len
     &				 )

c           ------------------------------------------------------
c           copy back to node vectors
c           ------------------------------------------------------

	    bwrite = .false.
	    do l=0,nlev
	      numv(l,k) = num(l)
	      nuhv(l,k) = nuh(l)
	      tken(l,k) = ken(l)
	      eps(l,k)  = dis(l)
	      rls(l,k)  = len(l)

	      rlmax = max(rlmax,len(l))	!ggu
	      if( len(l) .gt. 100. ) then
		nltot = nltot + 1
		bwrite = .true.
	      end if

	    end do

	    bwrite = .false.
	    if( bwrite ) then

	      !write(45,*) it,k
	      !call save_gotm_write

	      write(89,*) '==========================='
	      write(89,*) 'time___: ',it
	      write(89,*) 'node___: ',k
	      write(89,*) 'nlev___: ',nlev
	      write(89,*) 'dt_____: ',dt
	      write(89,*) 'depth__: ',depth
	      write(89,*) 'utaus_b: ',u_taus,u_taub
	      write(89,*) 'z0s_z0b: ',z0s,z0b
	      write(89,*) 'hh_____: ',(hh     (l),l=0,nlev)
	      write(89,*) 'nn_____: ',(nn     (l),l=0,nlev)
	      write(89,*) 'ss_____: ',(ss     (l),l=0,nlev)
	      write(89,*) 'num_old: ',(num_old(l),l=0,nlev)
	      write(89,*) 'nuh_old: ',(nuh_old(l),l=0,nlev)
	      write(89,*) 'ken_old: ',(ken_old(l),l=0,nlev)
	      write(89,*) 'dis_old: ',(dis_old(l),l=0,nlev)
	      write(89,*) 'len_old: ',(len_old(l),l=0,nlev)
	      write(89,*) 'num____: ',(num    (l),l=0,nlev)
	      write(89,*) 'nuh____: ',(nuh    (l),l=0,nlev)
	      write(89,*) 'ken____: ',(ken    (l),l=0,nlev)
	      write(89,*) 'dis____: ',(dis    (l),l=0,nlev)
	      write(89,*) 'len____: ',(len    (l),l=0,nlev)
	      write(89,*) '==========================='
	    end if

c           ------------------------------------------------------
c           update viscosity and diffusivity
c           ------------------------------------------------------

	    do l=0,nlev
	      laux = nlev - l
	      visv(l,k) = num(laux)
	      difv(l,k) = nuh(laux)
	    end do

    1     continue
	end do

	call checka(nlvdim,shearf2,buoyf2,taub)

	call write_xfn
 
	!write(70,*) 'rlmax: ',it,rlmax,nltot

	ks = 0			!internal node number
	ioutfreq = 3600		!output frequency
	if( ks .gt. 0 .and. mod(it,ioutfreq) .eq. 0 ) then
	  write(188,*) it,nlev,(visv(l,ks),l=1,nlev)
	  write(189,*) it,nlev,(difv(l,ks),l=1,nlev)
	end if

c------------------------------------------------------
c end of routine
c------------------------------------------------------

	end

c**************************************************************

	subroutine gotm_init

c initializes gotm arrays

	implicit none

	include 'param.h'

        integer nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        integer nlvdi,nlv
        common /nkonst/ nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        common /level/ nlvdi,nlv

	double precision numv(0:nlvdim,nkndim)	!viscosity (momentum)
	double precision nuhv(0:nlvdim,nkndim)	!diffusivity (scalars)
	double precision tken(0:nlvdim,nkndim)	!turbulent kinetic energy
	double precision eps (0:nlvdim,nkndim)	!dissipation rate
	double precision rls (0:nlvdim,nkndim)	!length scale

        common /numv/numv
        common /nuhv/nuhv
        common /tken_gotm/tken
        common /eps_gotm/eps
        common /rls_gotm/rls

	save /numv/,/nuhv/,/tken_gotm/,/eps_gotm/,/rls_gotm/

	integer l,k
        double precision num_min, nuh_min
        double precision tken_min, eps_min, rls_min

        num_min = 1.e-6
        nuh_min = 1.e-6
        tken_min = 1.e-10
        eps_min = 1.e-12
        rls_min = 1.e-10

        do k=1,nkn
          do l=0,nlv
            numv(l,k) = num_min
            nuhv(l,k) = nuh_min
            tken(l,k) = tken_min
            eps(l,k)  = eps_min
            rls(l,k)  = rls_min
          end do
        end do

	end

c**************************************************************

	subroutine gotm_get(k,nlev,num,nuh,tk,ep,rl)

c returns internal parameters from turbulence closure

	implicit none

	integer k		!node
	integer nlev		!number of levels to return
	real num(0:nlev)	!viscosity
	real nuh(0:nlev)	!diffusivity
	real tk (0:nlev)	!kinetic energy
	real ep (0:nlev)	!dissipation
	real rl (0:nlev)	!length scale

	include 'param.h'

	double precision numv(0:nlvdim,nkndim)	!viscosity (momentum)
	double precision nuhv(0:nlvdim,nkndim)	!diffusivity (scalars)
	double precision tken(0:nlvdim,nkndim)	!turbulent kinetic energy
	double precision eps (0:nlvdim,nkndim)	!dissipation rate
	double precision rls (0:nlvdim,nkndim)	!length scale

        common /numv/numv
        common /nuhv/nuhv
        common /tken_gotm/tken
        common /eps_gotm/eps
        common /rls_gotm/rls

	save /numv/,/nuhv/,/tken_gotm/,/eps_gotm/,/rls_gotm/

	integer l,laux

        do l=0,nlev
	  laux = nlev - l
          num(l) = numv(laux,k)
          nuh(l) = nuhv(laux,k)
          tk(l)  = tken(laux,k)
          ep(l)  = eps (laux,k)
          rl(l)  = rls (laux,k)
        end do

	end

c**************************************************************

      subroutine Yevol(Nmx,dt,h,nuh,difmol,Qsour,Yvar,Yd,
     &                 Bcup,Yup,Bcdw,Ydw,Taur)

      implicit none

	integer Nmx		!number of levels
	real dt			!time step [s]
	real h(Nmx)		!level thickness [m]
	real nuh(0:Nmx)		!turbulent diffusivity [m**2/s]
	real difmol		!molecular diffusivity [m**2/s]
	real Qsour(Nmx)		!internal source term
	real Yvar(Nmx)		!variable to diffuse
	real Yd(Nmx)		!relaxation value for variable
	integer Bcup		!type of boundary condition (upper)
	real Yup		!value for boundary condition (upper)
	integer Bcdw		!type of boundary condition (lower)
	real Ydw		!value for boundary condition (lower)
	real Taur		!time scale to use with Yd [s]

c if Taur <= 0	-> do not use Yd
c Bcup/Bcdw :   1 = Neuman condition   2 = Dirichlet condition
c Yup,Ydw   :   value to use for boundary condition
c
c example: Bcup = 1  and Yup = 0  --> no flux condition across surface

!     This subroutine computes the evolution of any 
!     state variable "Y" after Mixing/Advection/Source
!     - with Neuman    Boundary Condition: Bc=1
!     - with Dirichlet Boundary Condition: Bc=2
!     Convention: fluxex are taken positive upward

	integer MaxNmx
	parameter(MaxNmx = 500)

	integer i
	double precision au(0:MaxNmx),bu(0:MaxNmx)
	double precision cu(0:MaxNmx),du(0:MaxNmx)
	double precision avh(0:MaxNmx),Y(0:MaxNmx)
	double precision cnpar,a,c

	if( Nmx .gt. MaxNmx ) stop 'error stop Tridiagonal: MaxNmx'

      cnpar = 1.      		!Crank Nicholson parameter (implicit)

!
! copy to auxiliary values
!

	 Y(0) = 0.
	 avh(0) = 0.
	 do i=1,Nmx
	   Y(i) = Yvar(i)
	   avh(i) = nuh(i) + difmol
	 end do

! Water column 
! => [a b c].X=[d] where X=[2, ...,i,i+1,...Nmx-1]

         do i=2,Nmx-1
          c    =2*dt*avh(i)  /(h(i)+h(i+1))/h(i) 
          a    =2*dt*avh(i-1)/(h(i)+h(i-1))/h(i)
          cu(i)=-cnpar*c                                 !i+1,n+1
          au(i)=-cnpar*a                                 !i-1,n+1
          bu(i)=1-au(i)-cu(i)                            !i  ,n+1
          du(i)=Y(i)+dt*Qsour(i)                         !i  ,n
     &          +(1-cnpar)*(a*Y(i-1)-(a+c)*Y(i)+c*Y(i+1))
         end do

! Surface 
! => [a b /].X=[d] where X=[Nmx-1,Nmx,/]

         if (Bcup.eq.1) then                       !BC Neuman
          a      =2*dt*avh(Nmx-1)/(h(Nmx)+h(Nmx-1))/h(Nmx)
          au(Nmx)=-cnpar*a
          bu(Nmx)=1-au(Nmx)
          du(Nmx)=Y(Nmx)
     &            +dt*(Qsour(Nmx)-Yup/h(Nmx))   
     &            +(1-cnpar)*a*(Y(Nmx-1)-Y(Nmx))
         else if (Bcup.eq.2) then                    !BC Dirichlet
          au(Nmx)=0.
          bu(Nmx)=1.
          du(Nmx)=Yup
         end if

! Bottom  
! => [/ b c].X=[d] where X=[/,1,2]

         if (Bcdw.eq.1) then                        !BC Neuman              
          c    =2*dt*avh(1)/(h(1)+h(2))/h(1)
          cu(1)=-cnpar*c 
          bu(1)=1-cu(1)
          du(1)=Y(1)             
     &          +dt*(Qsour(1)+Ydw/h(1))
     &          +(1-cnpar)*c*(Y(2)-Y(1))
         else if (Bcdw.eq.2) then                    !BC Dirichlet
          cu(1)=0.
          bu(1)=1.
          du(1)=Ydw
         end if
!
! Implicit internal restoring
!
         if ( Taur .gt. 0. .and. Taur .lt. 1.E10 ) then
          do i=1,Nmx
           bu(i)=bu(i)+dt/Taur
           du(i)=du(i)+dt/Taur*Yd(i)
          end do
         end if
!
! Implicit vertical mixing
!

         call Tridiagonal(Nmx,1,Nmx,au,bu,cu,du,Y)

	 do i=1,Nmx
	   Yvar(i) = Y(i)
	 end do

      return
      end

c**************************************************************

      subroutine Tridiagonal(Nmx,fi,lt,au,bu,cu,du,value)
      implicit none

	integer MaxNmx
	parameter(MaxNmx=500)
!
! !USES:
!
! !INPUT PARAMETERS:
      integer Nmx
      integer fi,lt
      double precision au(0:Nmx),bu(0:Nmx),cu(0:Nmx),du(0:Nmx)
!
! !OUTPUT PARAMETERS:
      double precision value(0:Nmx)
!
! !DESCRIPTION:
!     Used trough out the program.
!
! !BUGS:
!
! !SEE ALSO:
!
! !SYSTEM ROUTINES:
!
! !FILES USED:
!
! !REVISION HISTORY:
!
!  25Nov98   The GOTM developers  Initial code.
!
! !LOCAL VARIABLES:
      double precision ru(0:MaxNmx),qu(0:MaxNmx)
      integer i
!
!EOP
!BOC
	if( Nmx .gt. MaxNmx ) stop 'error stop Tridiagonal: MaxNmx'

      ru(lt)=au(lt)/bu(lt)
      qu(lt)=du(lt)/bu(lt)

      do i=lt-1,fi+1,-1
         ru(i)=au(i)/(bu(i)-cu(i)*ru(i+1))
         qu(i)=(du(i)-cu(i)*qu(i+1))/(bu(i)-cu(i)*ru(i+1))
      end do

      qu(fi)=(du(fi)-cu(fi)*qu(fi+1))/(bu(fi)-cu(fi)*ru(fi+1))

      value(fi)=qu(fi)
      do i=fi+1,lt
         value(i)=qu(i)-ru(i)*value(i-1)
      end do

      return
      end
!EOC

c**************************************************************

	subroutine setm2n2(nldim,buoyf2,shearf2)

c sets buoyancy and shear frequency
c
c this is done directly for each node
c in rhov is already rho^prime = rho - rho0 (deviation)
!  Discretisation of vertical shear squared according to Burchard (2002)
!  in order to guarantee conservation of kinetic energy when transformed
!  from mean kinetic energy to turbulent kinetic energy.
c
c bug fix in computation of shearf2 -> abs() statements to avoid negative vals

	implicit none

	integer nldim
	real buoyf2(nldim,1)
	real shearf2(nldim,1)

	include 'param.h'

        integer nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        common /nkonst/ nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        real grav,fcor,dcor,dirn,rowass,roluft
        common /pkonst/ grav,fcor,dcor,dirn,rowass,roluft
        integer itanf,itend,idt,nits,niter,it
        common /femtim/ itanf,itend,idt,nits,niter,it

        real rhov(nlvdim,nkndim)
        common /rhov/rhov
	real uprv(nlvdim,nkndim)
	common /uprv/uprv
	real vprv(nlvdim,nkndim)
	common /vprv/vprv
        real upro(nlvdim,1)
        common /upro/upro
        real vpro(nlvdim,1)
        common /vpro/vpro

	integer k,l,nlev
	real aux,dh,du,dv,m2,dbuoy
	real h(nlvdim)
	real cnpar			!numerical "implicitness" parameter
	real n2max,n2
	real nfreq,nperiod

	integer iuinfo
	save iuinfo
	data iuinfo / 0 /
 
	if( nldim .ne. nlvdim ) stop 'error stop setbuoyf: dimension'

        aux = -grav / rowass
	cnpar = 1
	n2max = 0.
 
        do k=1,nkn
          call dep3dnod(k,+1,nlev,h)
          do l=1,nlev-1
            dh = 0.5 * ( h(l) + h(l+1) )
            dbuoy = aux * ( rhov(l,k) - rhov(l+1,k) )
            n2 = dbuoy / dh
	    n2max = max(n2max,n2)
            buoyf2(l,k) = n2

            du = 0.5*(
     &       (cnpar*abs((uprv(l+1,k)-uprv(l,k))
     &		*(uprv(l+1,k)-upro(l,k)))+
     &       (1.-cnpar)*abs((upro(l+1,k)-upro(l,k))
     &		*(upro(l+1,k)-uprv(l,k))))
     &       /dh/h(l)
     &      +(cnpar*abs((uprv(l+1,k)-uprv(l,k))
     &		*(upro(l+1,k)-uprv(l,k)))+
     &       (1.-cnpar)*abs((upro(l+1,k)-upro(l,k))
     &		*(uprv(l+1,k)-upro(l,k))))
     &       /dh/h(l+1)
     &                )

            dv = 0.5*(
     &       (cnpar*abs((vprv(l+1,k)-vprv(l,k))
     &		*(vprv(l+1,k)-vpro(l,k)))+
     &       (1.-cnpar)*abs((vpro(l+1,k)-vpro(l,k))
     &		*(vpro(l+1,k)-vprv(l,k))))
     &       /dh/h(l)
     &      +(cnpar*abs((vprv(l+1,k)-vprv(l,k))
     &		*(vpro(l+1,k)-vprv(l,k)))+
     &       (1.-cnpar)*abs((vpro(l+1,k)-vpro(l,k))
     &		*(vprv(l+1,k)-vpro(l,k))))
     &       /dh/h(l+1)
     &                )

            !m2 = du**2 + dv**2
            m2 = du + dv
            shearf2(l,k) = m2
          end do
        end do

	nfreq = sqrt(n2max)
	nperiod = 0.
	if( nfreq .gt. 0. ) nperiod = 1. / nfreq
	if( iuinfo .le. 0 ) call getinfo(iuinfo)
	write(iuinfo,*) 'n2max: ',it,n2max,nfreq,nperiod

	end

c**************************************************************

	subroutine bnstress(czdef,taub,areaac)

c computes bottom stress at nodes
c
c this is evaluated for every element and then averaged for each node
c taub (stress at bottom) is accumulated and weighted by area
 
	implicit none

	real czdef
	real taub(1)
	real areaac(1)

	include 'param.h'
	include 'ev.h'

        integer nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        common /nkonst/ nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw

	integer nen3v(1)
	common /nen3v/nen3v
	real ulnv(nlvdim,neldim)
	common /ulnv/ulnv
	real vlnv(nlvdim,neldim)
	common /vlnv/vlnv
        integer ilhv(1)
        common /ilhv/ilhv

	integer k,ie,ii,n,nlev,ibase
	real aj,taubot

c	---------------------------------------------------
c	initialize arrays
c	---------------------------------------------------

        do k=1,nkn
          taub(k) = 0.
          areaac(k) = 0.
        end do
 
c	---------------------------------------------------
c	accumulate
c	---------------------------------------------------

        do ie=1,nel
 
          call elebase(ie,n,ibase)
          aj = ev(10,ie)
	  nlev = ilhv(ie)

          taubot = czdef * ( ulnv(nlev,ie)**2 + vlnv(nlev,ie)**2 )
          do ii=1,n
            k = nen3v(ibase+ii)
            taub(k) = taub(k) + taubot * aj
            areaac(k) = areaac(k) + aj
          end do

	end do

c	---------------------------------------------------
c	compute bottom stress
c	---------------------------------------------------

        do k=1,nkn
          if( areaac(k) .le. 0. ) stop 'error stop bnstress: (2)'
          taub(k) = taub(k) / areaac(k)
        end do

	end

c**************************************************************

	subroutine notused
 
c this is evaluated for every element and then averaged for each node
c the average is weigthed with the volume of each element
c level l (for node) refers to interface between layers l and l+1
c
c taub (stress at bottom) is also accumulated and weighted by area

	include 'param.h'
 
        integer nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        common /nkonst/ nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw

	integer nen3v(1)
	common /nen3v/nen3v
	real rhov(nlvdim,nkndim)
	common /rhov/rhov
 
        real shearf2(nlvdim,nkndim)
        common /saux1/shearf2
        real buoyf2(nlvdim,nkndim)
        common /saux2/buoyf2
        real volf2(nlvdim,nkndim)
        common /saux3/volf2
        real taub(1)
        common /v1v/taub
        real areaac(1)
        common /v2v/areaac
 
        integer ilhv(1)
        common /ilhv/ilhv
        integer ilhkv(1)
        common /ilhkv/ilhkv
        real ulnv(nlvdim,neldim)
        common /ulnv/ulnv
        real vlnv(nlvdim,neldim)
        common /vlnv/vlnv

	real h(nlvdim)

	  czdef = getpar('czdef')

        do k=1,nkn
	  nlev = ilhkv(k)
	  do l=1,nlev
	    shearf2(l,k) = 0.
	    volf2(l,k) = 0.
	  end do
          taub(k) = 0.
          areaac(k) = 0.
        end do
 
        do ie=1,nel
 
          call dep3dele(ie,+1,nlev,h)
          call elebase(ie,n,ibase)
          area = areaele(ie)
          arean = area/n
 
          do l=1,nlev-1
            dh = 0.5 * (h(l)+h(l+1))
            du = ulnv(l,ie) - ulnv(l+1,ie)
            dv = vlnv(l,ie) - vlnv(l+1,ie)
            m2 = (du**2 + dv**2) / dh**2
            vol = dh * arean
            do ii=1,n
              k = nen3v(ibase+ii)
              shearf2(l,k) = shearf2(l,k) + m2 * vol
              volf2(l,k) = volf2(l,k) + vol
            end do
          end do
 
          taubot = czdef * ( ulnv(nlev,ie)**2 + vlnv(nlev,ie)**2 )
          do ii=1,n
            k = nen3v(ibase+ii)
            taub(k) = taub(k) + taubot * arean
            areaac(k) = areaac(k) + arean
          end do
 
        end do
 
        do k=1,nkn
          nlev = ilhkv(k)
          do l=1,nlev-1
            if( volf2(l,k) .le. 0. ) stop 'error stop ... (1)'
            shearf2(l,k) = shearf2(l,k) / volf2(l,k)
          end do
          if( areaac(k) .le. 0. ) stop 'error stop ... (2)'
          taub(k) = taub(k) / areaac(k)
        end do

	end

c**************************************************************

	subroutine checka(nldim,shearf2,buoyf2,taub)

c checks arrays for nan or other strange values

	implicit none

	integer nldim
	real buoyf2(nldim,1)
	real shearf2(nldim,1)
	real taub(1)

	include 'param.h'

        integer nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        common /nkonst/ nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw

        real visv(0:nlvdim,nkndim)
        common /visv/visv
        real difv(0:nlvdim,nkndim)
        common /difv/difv

        real ulnv(nlvdim,neldim)
        common /ulnv/ulnv
        real vlnv(nlvdim,neldim)
        common /vlnv/vlnv
        real uprv(nlvdim,nkndim)
        common /uprv/uprv
        real vprv(nlvdim,nkndim)
        common /vprv/vprv
        real tauxnv(1),tauynv(1)
        common /tauxnv/tauxnv,/tauynv/tauynv

	if( nlvdim .ne. nldim ) stop 'error stop checka'

	call nantest(nkn*nlvdim,shearf2,'shearf2')
	call nantest(nkn*nlvdim,buoyf2,'buoyf2')
	call nantest(nkn,taub,'taub')

	call nantest(nkn*(nlvdim+1),visv,'visv')
	call nantest(nkn*(nlvdim+1),difv,'difv')

	call nantest(nkn*nlvdim,uprv,'uprv')
	call nantest(nkn*nlvdim,vprv,'vprv')
	call nantest(nel*nlvdim,ulnv,'ulnv')
	call nantest(nel*nlvdim,vlnv,'vlnv')

	call nantest(nkn,tauxnv,'tauxnv')
	call nantest(nkn,tauynv,'tauynv')
 
	end

c**************************************************************

	subroutine checkb(text)

c checks arrays for strange values

	implicit none

	character*(*) text

	include 'param.h'

        integer nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        common /nkonst/ nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw

        real visv(0:nlvdim,nkndim)
        common /visv/visv
        real difv(0:nlvdim,nkndim)
        common /difv/difv

	real znv(1)
	common /znv/znv
	real zenv(3,1)
	common /zenv/zenv

	real rhov(nlvdim,nkndim)
	common /rhov/rhov
        real ulnv(nlvdim,neldim)
        common /ulnv/ulnv
        real vlnv(nlvdim,neldim)
        common /vlnv/vlnv
        real utlnv(nlvdim,neldim)
        common /utlnv/utlnv
        real vtlnv(nlvdim,neldim)
        common /vtlnv/vtlnv
        real uprv(nlvdim,nkndim)
        common /uprv/uprv
        real vprv(nlvdim,nkndim)
        common /vprv/vprv
        real tauxnv(1),tauynv(1)
        common /tauxnv/tauxnv,/tauynv/tauynv

	integer one,three
	real zero,valmax
	real amin,amax

	one = 1
	three = 3
	zero = 0.

	valmax = 5.
	call valtest(one,nkn,-valmax,valmax,znv,text,'znv')
	call valtest(three,nel,-valmax,valmax,zenv,text,'zenv')

	valmax = 10000.
	call valtest(nlvdim+1,nkn,zero,valmax,visv,text,'visv')
	call valtest(nlvdim+1,nkn,zero,valmax,difv,text,'difv')

	valmax = 100.
	call valtest(nlvdim,nkn,-valmax,valmax,rhov,text,'rhov')

	valmax = 3.
	call valtest(nlvdim,nel,-valmax,valmax,ulnv,text,'ulnv')
	call valtest(nlvdim,nel,-valmax,valmax,vlnv,text,'vlnv')

	valmax = 100.
	call valtest(nlvdim,nel,-valmax,valmax,utlnv,text,'utlnv')
	call valtest(nlvdim,nel,-valmax,valmax,vtlnv,text,'vtlnv')

	end

c**************************************************************

	subroutine keps_shell

	implicit none

	include 'param.h'

        integer nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        common /nkonst/ nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw

        integer ilhkv(1)
        common /ilhkv/ilhkv

        real hdknv(nlvdim,nkndim)
        common /hdknv/hdknv

        real uprv(nlvdim,nkndim),vprv(nlvdim,nkndim)
        common /uprv/uprv, /vprv/vprv

        real rhov(nlvdim,nkndim)
        real visv(0:nlvdim,nkndim)      !viscosity (momentum)
        real difv(0:nlvdim,nkndim)      !diffusivity (scalars)

        real tken(0:nlvdim,nkndim)      !turbulent kinetic energy
        real eps(0:nlvdim,nkndim)       !dissipation rate
        real rls(0:nlvdim,nkndim)       !length scale

        common /rhov/rhov
        common /visv/visv      !viscosity (momentum)
        common /difv/difv      !diffusivity (scalars)

        common /tken/tken      !turbulent kinetic energy
        common /eps/eps        !dissipation rate
        common /rls/rls        !length scale

	integer k,lmax,l
	real rho0,rhoair
	real cd,cb
	real wx,wy
	real ubot,vbot
	real dtreal,dt
	real taus,taub

	integer icall
	save icall
	data icall /0/

	if( icall .eq. 0 ) then
	  call keps_init
	  icall = 1
	end if

	call get_timestep(dtreal)
	dt = dtreal
	rho0 = 1024.
	rhoair = 1.225
	cd = 2.5e-3
	cb = 2.5e-3

	do k=1,nkn

	  lmax = ilhkv(k)
	  ubot = uprv(lmax,k)
	  vbot = vprv(lmax,k)
	  call get_wind(k,wx,wy)
	  taus = rhoair * cd * (wx*wx+wy*wy)
	  taub = rho0 * cb * (ubot*ubot+vbot*vbot)

          call keps(lmax,dt,rho0
     +		,taus,taub
     +		,hdknv(1,k),uprv(1,k),vprv(1,k)
     +		,rhov(1,k),visv(0,k),difv(0,k),tken(0,k),eps(0,k))

	end do

	end

c**************************************************************

        subroutine keps_init

c initializes arrays for keps routine

        implicit none

	real kmin,epsmin,lenmin,avumol,avtmol,avsmol
c       parameter(kmin=1.e-10,epsmin=1.e-12,lenmin=0.01)
        parameter(kmin=3.e-6,epsmin=5.e-10,lenmin=0.01)
        parameter(avumol=1.3e-6,avtmol=1.4e-7,avsmol=1.1e-9)

	include 'param.h'

        integer nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw
        common /nkonst/ nkn,nel,nrz,nrq,nrb,nbc,ngr,mbw

        real visv(0:nlvdim,nkndim)      !viscosity (momentum)
        real difv(0:nlvdim,nkndim)      !diffusivity (scalars)

        real tken(0:nlvdim,nkndim)      !turbulent kinetic energy
        real eps(0:nlvdim,nkndim)       !dissipation rate
        real rls(0:nlvdim,nkndim)       !length scale

        common /visv/visv      !viscosity (momentum)
        common /difv/difv      !diffusivity (scalars)

        common /tken/tken      !turbulent kinetic energy
        common /eps/eps        !dissipation rate
        common /rls/rls        !length scale

        integer k,l

	do k=1,nkn
          do l=0,nlvdim
            tken(l,k) = kmin
            eps(l,k) = epsmin
            rls(l,k) = lenmin
            visv(l,k) = avumol
            difv(l,k) = avsmol
	  end do
        end do

        end

c**************************************************************
c**************************************************************
c debug routines
c**************************************************************
c**************************************************************

	subroutine write_node_vel_info(iunit,it,k,ndim,depth
     +			,u_taus,u_taub,z0s,z0b
     +			,num,nuh,ken,dis,len,nn,ss,hh)

	implicit none

	integer iunit,it,k,ndim
	double precision depth,u_taus,u_taub,z0s,z0b

	double precision hh(0:ndim)
	double precision nn(0:ndim), ss(0:ndim)

	double precision num(0:ndim), nuh(0:ndim)
	double precision ken(0:ndim), dis(0:ndim)
	double precision len(0:ndim)

	integer l

	write(iunit,*) '----------------------------------'
	write(iunit,*) 'time,node,nlev: ',it,k,ndim
	write(iunit,*) 'depth: ',depth
	write(iunit,*) 'u_taus,u_taub: ',u_taus,u_taub
	write(iunit,*) 'z0s,z0b: ',z0s,z0b
	write(iunit,*) 'num:',(num(l),l=0,ndim)
	write(iunit,*) 'nuh:',(nuh(l),l=0,ndim)
	write(iunit,*) 'ken:',(ken(l),l=0,ndim)
	write(iunit,*) 'dis:',(dis(l),l=0,ndim)
	write(iunit,*) 'len:',(len(l),l=0,ndim)
	write(iunit,*) 'nn :',(nn(l),l=0,ndim)
	write(iunit,*) 'ss :',(ss(l),l=0,ndim)
	write(iunit,*) 'hh :',(hh(l),l=0,ndim)

	end

c**************************************************************

	subroutine write_node_bin_info(iunit,it,k,ndim,depth
     +			,u_taus,u_taub,z0s,z0b
     +			,num,nuh,ken,dis,len,nn,ss,hh)

	implicit none

	integer iunit,it,k,ndim
	double precision depth,u_taus,u_taub,z0s,z0b

	double precision hh(0:ndim)
	double precision nn(0:ndim), ss(0:ndim)

	double precision num(0:ndim), nuh(0:ndim)
	double precision ken(0:ndim), dis(0:ndim)
	double precision len(0:ndim)

	integer l

	write(iunit) it,k,ndim
	write(iunit) depth
	write(iunit) u_taus,u_taub
	write(iunit) z0s,z0b
	write(iunit) (num(l),l=0,ndim)
	write(iunit) (nuh(l),l=0,ndim)
	write(iunit) (ken(l),l=0,ndim)
	write(iunit) (dis(l),l=0,ndim)
	write(iunit) (len(l),l=0,ndim)
	write(iunit) (nn(l),l=0,ndim)
	write(iunit) (ss(l),l=0,ndim)
	write(iunit) (hh(l),l=0,ndim)

	end

c**************************************************************

	subroutine set_debug_ggu( debug )

	implicit none

	logical debug
	logical bdebug
	common /debug_ggu/bdebug
	save /debug_ggu/

	bdebug = debug

	end

c**************************************************************

	subroutine get_debug_ggu( debug )

	implicit none

	logical debug
	logical bdebug
	common /debug_ggu/bdebug
	save /debug_ggu/

	debug = bdebug

	end

c**************************************************************

