<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path="">
    <Project_Created_Time></Project_Created_Time>
    <TD_Encoding>UTF-8</TD_Encoding>
    <TD_Version>6.2.168116</TD_Version>
    <Name>tf_probe</Name>
    <HardWare>
        <Family>PH1</Family>
        <Device>PH1P35MDG324</Device>
        <Speed>-3</Speed>
    </HardWare>
    <MiscSettings>
        <Setting Key="farm" Val="disable" />
    </MiscSettings>
    <Source_Files>
<Verilog>
        <File Path="../rtl/sd_spi_byte.v">
            <FileInfo>
                <Attr Name="UsedInSyn" Val="true"/>
                <Attr Name="UsedInP&R" Val="true"/>
                <Attr Name="BelongTo" Val="design_1"/>
                <Attr Name="CompileOrder" Val="1"/>
            </FileInfo>
        </File>
        <File Path="../rtl/tf_probe_top.v">
            <FileInfo>
                <Attr Name="UsedInSyn" Val="true"/>
                <Attr Name="UsedInP&R" Val="true"/>
                <Attr Name="BelongTo" Val="design_1"/>
                <Attr Name="CompileOrder" Val="2"/>
            </FileInfo>
        </File>
</Verilog>
<ADC_FILE>
        <File Path="tf_probe.adc">
            <FileInfo>
                <Attr Name="UsedInSyn" Val="true"/>
                <Attr Name="UsedInP&R" Val="true"/>
                <Attr Name="BelongTo" Val="constraint_1"/>
                <Attr Name="CompileOrder" Val="3"/>
            </FileInfo>
        </File>
</ADC_FILE>
<SDC_FILE>
        <File Path="tf_probe.sdc">
            <FileInfo>
                <Attr Name="UsedInSyn" Val="true"/>
                <Attr Name="UsedInP&R" Val="true"/>
                <Attr Name="BelongTo" Val="constraint_1"/>
                <Attr Name="CompileOrder" Val="4"/>
            </FileInfo>
        </File>
</SDC_FILE>
</Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles">
        </FileSet>
        <FileSet Name="constraint_1" Type="ConstrainFiles">
        </FileSet>
    </FileSets>
    <TOP_MODULE>
        <LABEL>tf_probe_top</LABEL>
        <MODULE>tf_probe_top</MODULE>
        <CREATEINDEX>user</CREATEINDEX>
    </TOP_MODULE>
    <Property>
    </Property>
    <Device_Settings>
    </Device_Settings>
    <Configurations>
        <Control0>
            <mclk_freq>33MHz</mclk_freq>
        </Control0>
        <FeatureRow>
            <boot_mode>mspix4</boot_mode>
        </FeatureRow>
    </Configurations>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true" useDefaultScript="false">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy">
                <BitgenProperty::GeneralOption>
                    <compress>on</compress>
                </BitgenProperty::GeneralOption>
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
    </Runs>
    <Project_Settings>
    </Project_Settings>
</Project>
