# Remastered submarine test mod

In the game, press **F1**, select **Mods**, enable **Test: remastered submarine**,
then choose **Apply and reload**. In the editor, click **Mods** beside **Assets** and **Map**.
If another submarine replacement is enabled, put this mod later in the list
so it takes priority.

This uses `SubCulture_Submarine_Game.glb` from the supplied
`Other resources/SubCulture_Submarine_v0.4` package, with its embedded textures.
The source's internal scale is retained, followed by the game's existing
submarine scale. Pods and all three propellers use the existing animation,
bubble and sound systems. Movement and collision settings remain the game's
current settings. Disable the mod and apply to restore the original model.

To test a revised export, replace `models/submarine.glb` and apply again.
Keep the moving node hierarchy or update the paths in `mod.json`.
